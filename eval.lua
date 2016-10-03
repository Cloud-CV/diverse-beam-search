require 'torch'
require 'nn'
require 'nngraph'
require 'debug'
-- exotics
require 'loadcaffe'
-- local imports
utils = require 'misc.utils'
require 'misc.DataLoader'
require 'misc.DataLoaderRaw'
require 'misc.LanguageModel'
net_utils = require 'misc.net_utils'
beam_utils = require 'dbs.beam_utils'
div_utils = require 'dbs.div_utils'
vis_utils = require 'misc.vis_utils'

local debug = require 'debug'

local TorchModel = torch.class('DBSTorchModel')

function TorchModel:__init(model, batch_size, language_eval, dump_images, dump_json, dump_json_postfix, dump_path, B, M, lambda, divmode, temperature, ngram_length, image_root, input_h5, input_json, split, coco_json, backend, id, seed, gpuid, div_vis_dir)

  -- Input option
  self.model = model

  -- Basic option
  self.batch_size = batch_size
  -- self.num_images = num_images
  self.language_eval = language_eval
  self.dump_images = dump_images
  self.dump_json = dump_json
  self.dump_json_postfix = dump_json_postfix
  self.dump_path = dump_path

  -- Sampling Option
  self.B = B
  self.M = M
  self.lambda = lambda
  self.divmode = divmode
  self.temperature = temperature
  -- self.primetext = primetext
  self.ngram_length = ngram_length

  -- For evaluation on a folder of images
  -- self.image_folder = image_folder
  self.image_root = image_root

  -- For evaluation on MSCOCO images from some split
  self.input_h5 = input_h5
  self.input_json = input_json
  self.split = split
  self.coco_json = coco_json

  -- Misc Options
  self.backend = backend
  self.id = id
  self.seed = seed
  self.gpuid = gpuid
  self.div_vis_dir = div_vis_dir

  self:loadModel()

  torch.manualSeed(self.seed)
  torch.setdefaulttensortype('torch.FloatTensor')

  if self.gpuid >= 0 then
    require 'cutorch'
    require 'cunn'
    if self.backend == 'cudnn' then require 'cudnn' end
    cutorch.manualSeed(self.seed)
    cutorch.setDevice(self.gpuid + 1) -- note +1 because lua is 1-indexed
  end

  local export_div_vis = (self.div_vis_dir ~= '')
end


function TorchModel:loadModel()

  local function table_invert(t)
    -------------------------------------------------------------------------------
    -- invert vocab
    -------------------------------------------------------------------------------
    local s = {}
    for k,v in pairs(t) do
        s[v] = k
    end
    return s
  end 

  local function convert_vocab_keys_to_int(vocab)
    local result = {}
    for k,v in pairs(vocab) do
        result[tonumber(k)] = v
    end
    return result
  end
  -------------------------------------------------------------------------------
  -- Load the model checkpoint to evaluate
  -------------------------------------------------------------------------------
  assert(string.len(self.model) > 0, 'must provide a model')
  local checkpoint = torch.load(self.model)

  local fetch = {'rnn_size', 'input_encoding_size', 'drop_prob_lm', 'cnn_proto', 'cnn_model', 'seq_per_img'}

  -- for k,v in pairs(fetch) do 
  --   opt[v] = checkpoint.opt[v] -- copy over options from model
  -- end

  local vocab = checkpoint.vocab -- ix -> word mapping
  local inv_vocab = table_invert(checkpoint.vocab)
  local vocab_int = convert_vocab_keys_to_int(vocab)

  local protos = checkpoint.protos
  protos.expander = nn.FeatExpander(checkpoint['seq_per_img'])
  protos.crit = nn.LanguageModelCriterion()
  protos.lm:createClones() -- reconstruct clones inside the language model
  if self.gpuid >= 0 then for k,v in pairs(protos) do v:cuda() end end

  self.protos = protos
  self.checkpoint = checkpoint
  self.vocab = vocab
end

-------------------------------------------------------------------------------
-- Evaluation fun(ction)
-------------------------------------------------------------------------------
function TorchModel:predict(image_folder, prefix)

  local loader = DataLoaderRaw{folder_path = image_folder, coco_json = self.coco_json}
  local num_images = self.num_images

  self.primetext = prefix
  self.image_folder = image_folder

  self.protos.cnn:evaluate()
  self.protos.lm:evaluate()
  self.loader:resetIterator(self.split) -- rewind iteator back to first datapoint in the split
  local n = 0
  local loss_sum = 0
  local loss_evals = 0
  local final_beams = {}
  while true do

    -- fetch a batch of data
    local data = self.loader:getBatch{batch_size = self.batch_size, split = self.split, seq_per_img = self.checkpoint['seq_per_img']}
    data.images = net_utils.prepro(data.images, false, self.gpuid >= 0) -- preprocess in place, and don't augment
    n = n + data.images:size(1)
    -- forward the model to get loss
    local feats = self.protos.cnn:forward(data.images)

    -- evaluate loss if we have the labels
    local loss = 0
    if data.labels then
      local expanded_feats = self.protos.expander:forward(feats)
      local logprobs = self.protos.lm:forward{expanded_feats, data.labels}
      loss = self.protos.crit:forward(logprobs, data.labels)
      loss_sum = loss_sum + loss
      loss_evals = loss_evals + 1
    end

    local function gen_logprobs(word_ix, state)
        local embedding = self.protos.lm.lookup_table:forward(word_ix)
        local inputs = {embedding, unpack(state)}
        return self.protos.lm.core:forward(inputs)
    end

    local w2vutils
    local idx2vec
    if self.divmode == 3 then
      w2vutils = require 'dbs.word2vec.w2vutils'
      idx2vec = function(seq_idx)
          word = vocab_int[seq_idx]
          vec = w2vutils:word2vec(word, false)
          return vec
      end
    end

    -- forward the model to also get generated samples for each image
    local sample_opts = {
        T = self.protos.lm.seq_length,
        B = self.B,
        M = self.M,
        lambda = self.lambda,
        temperature = self.temperature,
        -- size of a state
        state_size = self.protos.lm.num_layers * 2,
        rnn_size = self.protos.lm.rnn_size,
        end_token = self.protos.lm.vocab_size + 1,
        gen_logprobs = gen_logprobs,
        use_gpu = (self.gpuid >= 0),
        divmode = self.divmode,
        primetext = prefix,
        ngram_length = self.ngram_length,
        idx2vec = idx2vec,
    }
    if export_div_vis then
        vis_table = {}
        vis_table['iterations'] = {}
        sample_opts.vis_iterations = vis_table['iterations']
    end

    local function preproc_prime(prime)
        return prime:lower():gsub("%p", "")
    end

    -- prime lstm with image features embedded to vocab space
    local function prime_model() 
      -- forward 0 state and image embedding
      state = {}
      for i = 1,sample_opts.state_size do
          state[i] = torch.zeros(sample_opts.rnn_size)
          if sample_opts.use_gpu then
              state[i] = state[i]:cuda()
          end
      end
      local states_and_logprobs = self.protos.lm.core:forward({feats, unpack(state)})
      -- forward start token
      local start_token = torch.LongTensor(1):fill(self.protos.lm.vocab_size+1)
      if sample_opts.use_gpu then
          start_token = start_token:cuda()
      end
      for i = 1,sample_opts.state_size do
          state[i] = states_and_logprobs[i]:clone()
      end
      states_and_logprobs = gen_logprobs(start_token, state)
      -- get initial state for beam search
      local logprobs = states_and_logprobs[#states_and_logprobs]
      for i = 1,sample_opts.state_size do
          state[i] = states_and_logprobs[i]:clone()
      end
      
      for word in preproc_prime(self.primetext):gmatch'%w+' do
          ix = inv_vocab[word]
          if ix == nil then
              -- UNK
              ix = self.protos.lm.vocab_size
          end
          local ix_word = torch.LongTensor(1):fill(ix)
          if sample_opts.use_gpu then
              ix_word = ix_word:cuda()
          end
          states_and_logprobs = gen_logprobs(ix_word, state)
          for i = 1, sample_opts.state_size do
              state[i] = states_and_logprobs[i]:clone()
              logprobs = states_and_logprobs[#states_and_logprobs]
          end
      end
      
      local init = {}
      init[1] = state
      init[2] = logprobs
      return init
    end

    local init = prime_model()
    final_beams[n] = {}
    temp_name = string.split(data.infos[1].file_path,'/')
    final_beams[n]['image_id'] = temp_name[#temp_name]
    final_beams[n]['caption'] = beam_utils.beam_search(init, sample_opts)

    if export_div_vis then
        assert(self.batch_size == 1)
        img_path = data.infos[1].file_path
        vis_utils.export_vis(final_beams[n]['caption'], vis_table, img_path, self.vocab, T, self.div_vis_dir, sample_opts.end_token, sample_opts.primetext)
    end

    print('done with image: ' .. n)
    if data.bounds.wrapped then break end -- the split ran out of data, lets break out
    if num_images >= 0 and n >= num_images then break end -- we've used enough images
  end

  beam_table = final_beams

  -- print_and_dump_beam method
  print('\nOUTPUT:')
  print('----------------------------------------------------')

  local function compare_beam(a,b) return a.logp > b.logp end

  json_table = {}
  bdash = self.B / self.M

  for im_n = 1,#beam_table do
    json_table[im_n] = {}
    json_table[im_n]['image_id'] = beam_table[im_n]['image_id']
    json_table[im_n]['captions'] = {}
    for i = 1,self.M do
      for j = 1,bdash do
        current_beam_string = table.concat(net_utils.decode_sequence(vocab, torch.reshape(beam_table[im_n]['caption'][i][j].seq, beam_table[im_n]['caption'][i][j].seq:size(1), 1)))
        print('beam ' .. (i-1)*bdash+j ..' diverse group: '..i)
        print(string.format('%s',current_beam_string))
        print('----------------------------------------------------')
        json_table[im_n]['captions'][(i-1)*bdash+j] = {}
        json_table[im_n]['captions'][(i-1)*bdash+j]['logp'] = beam_table[im_n]['caption'][i][j].unaug_logp
        json_table[im_n]['captions'][(i-1)*bdash+j]['sentence'] = current_beam_string
      end
    end

    table.sort(json_table[im_n]['captions'],compare_beam)
  end
  if self.dump_json == 1 then
    -- dump the json
    utils.write_json('captions/vis_'..self.B..'_'..self.M..'_lambda'..self.lambda..'_divmode'..self.divmode..'_temp'..self.temperature..'_ngram'..self.ngram_length..'_'..self.dump_json_postfix..'.json', json_table)
  end
  return json_table
end

-- local beam_table  = eval_split(self.split, {num_images = self.num_images})
-- print_and_dump_beam(opt,beam_table)
