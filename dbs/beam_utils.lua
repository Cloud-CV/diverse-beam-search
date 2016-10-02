require 'dbs.util.misc' -- for table.slice
require 'debug'

local beam_utils = {}

-- function to compare
function beam_utils.compare(a,b) return a.p > b.p end

function beam_utils.clone_list(lst)
  -- takes list of tensors, clone all
  local new = {}
  for k,v in pairs(lst) do
    new[k] = v:clone()
  end
  return new
end

-- function computes the weighting factor for the diversity
function add_diversity(beam_seq_table,logprobsf,t,divm,opt,bdash)
  local local_time = t - divm + 1
  local unaug_logprobsf = logprobsf:clone()
  local this_group = beam_seq_table[divm]
  local function ngrams_equal(a, b)
    for i = 1,a:size(1) do
      if a[i] ~= b[i] then
        return false
      end
    end
    return true
  end
  local function ngram2vec(ngram)
    local vec = nil
    for i = 1,ngram:size(1) do
        if vec == nil then
            vec = opt.idx2vec(ngram[i])
        else
            vec = vec + opt.idx2vec(ngram[i])
        end
    end
    return vec
  end
  local function apply_div_penalty(this_int_group_i)
    -- all previous beams
    for prev_ext_group_i = 1, divm-1 do
      local prev_group = beam_seq_table[prev_ext_group_i]
      for prev_int_group_i = 1,bdash do 
        local last_end_time = local_time

        local first_end_time = local_time
        if opt.divmode == 2 then
          first_end_time = math.min(last_end_time, opt.ngram_length)
        end
        -- all ngrams in this prev beam
        for end_time = first_end_time,last_end_time do
          local start_time = math.max(1, end_time - opt.ngram_length + 1)
          local prev_ngram = prev_group[{{start_time, end_time}, prev_int_group_i}]
          local this_nm1gram = this_group[{{this_start_time, local_time}, this_int_group_i}]
          -- compare up to the last character
          local matches_to_last_char = true
          if start_time > end_time then
            local this_start_time = math.max(1, local_time - opt.ngram_length + 1)
            local prev_nm1gram = prev_group[{{start_time, end_time-1}, prev_int_group_i}]
            matches_to_last_char = ngrams_equal(this_nm1gram, prev_nm1gram)
          end
          -- 1, except when using cumulative diversity
          local div_multiplier = div_utils.cumulative_div(beam_seq_table,t,divm,opt.divmode)
          -- compare ngrams exactly
          if opt.divmode <= 2 then
            if matches_to_last_char then
              local final_word = prev_ngram[prev_ngram:size(1)]
              logprobsf[{this_int_group_i, final_word}] = logprobsf[{this_int_group_i, final_word}] - opt.lambda * div_multiplier
            end
          -- compare with word2vec
          elseif opt.divmode == 3 then
            local cosine_dist = nn.CosineDistance()
            local prev_vec = ngram2vec(prev_ngram)
            local wordps,likely_word_idxs = torch.sort(logprobsf[this_int_group_i], 1, true)
            for i = 1,50 do
              local final_word = likely_word_idxs[i]
              local this_vec = ngram2vec(this_nm1gram) + opt.idx2vec(final_word)
              local dist = cosine_dist:forward({prev_vec, this_vec})[1]
              logprobsf[{this_int_group_i, final_word}] = logprobsf[{this_int_group_i, final_word}] - opt.lambda * div_multiplier * dist
            end
          else
            error('unsupported divmode: '..opt.divmode)
          end
        end
      end
    end
  end

  -- penalize diversity for each beam
  for this_int_group_i = 1,bdash do
    apply_div_penalty(this_int_group_i)
  end
  return unaug_logprobsf
end

-- does one step of beam_step
local function beam_step(logprobsf,unaug_logprobsf,beam_size,t,beam_seq,beam_seq_logprobs,beam_logprobs_sum,state)
--INPUTS:
--logprobsf: probabilities augmented after diversity
--beam_size: obvious
--t        : time instant
--beam_seq : tensor contanining the beams
--beam_seq_logprobs: tensor contanining the beam logprobs
--beam_logprobs_sum: tensor contanining joint logprobs
--OUPUTS:
--beam_seq
--beam_seq_logprobs
--beam_logprobs_sum
  local ys,ix = torch.sort(logprobsf,2,true)
  local candidates = {}
  local cols = math.min(beam_size,ys:size()[2])
  local rows = beam_size
  if t == 1 then rows = 1 end
  for c=1,cols do -- for each column (word, essentially)
    for q=1,rows do -- for each beam expansion
    --compute logprob of expanding beam q with word in (sorted) position c
      local_logprob = ys[{ q,c }]
      candidate_logprob = beam_logprobs_sum[q] + local_logprob
			local_unaug_logprob = unaug_logprobsf[{q,ix[{q,c}]}]
      table.insert(candidates, {c=ix[{ q,c }], q=q, p=candidate_logprob, r=local_unaug_logprob })
    end
  end
  table.sort(candidates, beam_utils.compare)
  new_state = beam_utils.clone_list(state)
--local beam_seq_prev, beam_seq_logprobs_prev
  if t > 1 then
  --we''ll need these as reference when we fork beams around
    beam_seq_prev = beam_seq[{ {1,t-1}, {} }]:clone()
    beam_seq_logprobs_prev = beam_seq_logprobs[{ {1,t-1}, {} }]:clone()
  end
  for vix=1,beam_size do
    v = candidates[vix]
    v.kept = true
  --fork beam index q into index vix
    if t > 1 then
      beam_seq[{ {1,t-1}, vix }] = beam_seq_prev[{ {}, v.q }]
      beam_seq_logprobs[{ {1,t-1}, vix }] = beam_seq_logprobs_prev[{ {}, v.q }]
    end
  --rearrange recurrent states
    for state_ix = 1,#new_state do
--  copy over state in previous beam q to new beam at vix
      new_state[state_ix][vix] = state[state_ix][v.q]
    end
--append new end terminal at the end of this beam
    beam_seq[{ t, vix }] = v.c -- c'th word is the continuation
    beam_seq_logprobs[{ t, vix }] = v.r -- the raw logprob here
    beam_logprobs_sum[vix] = v.p -- the new (sum) logprob along this beam
  end
  state = new_state
  return beam_seq,beam_seq_logprobs,beam_logprobs_sum,state,candidates
end

-- implements beam search
-- calls beam_step and returns the final set of beams
function beam_utils.beam_search(init_params, opt)
  local bdash = opt.B / opt.M
  local init_state = init_params[1]
  local init_logprobs = init_params[2]
  local vis_iterations = opt.vis_iterations
  local export_vis = (vis_iterations ~= nil)
  local state_table = {}
  local beam_seq_table = {}
  local beam_seq_logprobs_table = {}
  local beam_logprobs_sum_table = {}
  -- INITIALIZATIONS
  for i=1,opt.M do
    state_table[i] = {}
  end
  for i=1,opt.M do
    beam_seq_table[i] = torch.Tensor(opt.T, bdash):zero()
    if opt.use_gpu then
        beam_seq_table[i] = beam_seq_table[i]:cuda()
    end
  end
  for i=1,opt.M do
    beam_seq_logprobs_table[i] = torch.Tensor(opt.T, bdash):zero()
    if opt.use_gpu then
        beam_seq_logprobs_table[i] = beam_seq_logprobs_table[i]:cuda()
    end
  end
  for i=1,opt.M do
    beam_logprobs_sum_table[i] = torch.zeros(bdash)
    if opt.use_gpu then
        beam_logprobs_sum_table[i] = beam_logprobs_sum_table[i]:cuda()
    end
  end
  -- logprobs -- logprobs predicted in last time step, shape (beam_size, vocab_size+1)
  done_beams_table = {}
  for i=1,opt.M do
    done_beams_table[i] = {}
  end
  state = {}
  for h =1,opt.state_size do
    state[h] = torch.zeros(bdash, opt.rnn_size)
    if opt.use_gpu then
        state[h] = state[h]:cuda()
    end
  end
  for h=1,opt.state_size do
    for b = 1, bdash do
      state[h][b] = init_state[h]:clone()
    end
  end
  for i=1,opt.M do
    state_table[i] = beam_utils.clone_list(state)
  end
  logprobs_table = {}
  for i=1,opt.M do 
    logprobs_table[i] = torch.zeros(bdash, init_logprobs:size()[2])
    if opt.use_gpu then
        logprobs_table[i] = logprobs_table[i]:cuda()
    end
    for j = 1,bdash do logprobs_table[i][j] = init_logprobs:clone() end
  end
  -- END INIT

  for t=1,opt.T+opt.M-1 do
    local vis_candidates = {}
    for divm = 1,opt.M do 
      if t>= divm and t<= opt.T+divm-1 then 
        -- add diversity
        logprobsf = logprobs_table[divm]
        local unaug_logprobsf = add_diversity(beam_seq_table,logprobsf,t,divm,opt,bdash)

        -- infer new beams
        beam_seq_table[divm],
        beam_seq_logprobs_table[divm],
        beam_logprobs_sum_table[divm],
        state_table[divm],
        candidates_divm = beam_step(logprobsf,
																		unaug_logprobsf,
                                    bdash,
                                    t-divm+1,
                                    beam_seq_table[divm],
                                    beam_seq_logprobs_table[divm],
                                    beam_logprobs_sum_table[divm],
                                    state_table[divm])

        -- cache candidates for visualization
        local candidates_kept_for_divm = {}
        if export_vis then
          for ci = 1,#candidates_divm do
            c = candidates_divm[ci]
            c.cid = #vis_candidates
            c.t = t
            c.t_prev = t - 1
            c.cid_prev = (divm - 1 - math.max(0, t - opt.T - 1)) * bdash * bdash + c.q
            c.local_t = t - divm + 1
            c.divm = divm
            table.insert(vis_candidates, c)
            if c.kept then
              table.insert(candidates_kept_for_divm, c)
            end
          end
          assert(#candidates_kept_for_divm == bdash)
        end

        -- if time's up... or if end token is reached then copy beams
        for vix=1,bdash do
          local is_first_end_token = ((beam_seq_table[divm][{ {},vix}][t-divm+1] == opt.end_token) and (torch.eq(beam_seq_table[divm][{ {},vix}],opt.end_token):sum()==1))
          local final_time_without_end_token = ((t == opt.T+divm-1) and (torch.eq(beam_seq_table[divm][{ {},vix}],opt.end_token):sum()==0))
          if is_first_end_token or final_time_without_end_token then
            final_beam = {
              seq = beam_seq_table[divm][{ {}, vix }]:clone(), 
              logps = beam_seq_logprobs_table[divm][{ {}, vix }]:clone(),
							unaug_logp = beam_seq_logprobs_table[divm][{ {}, vix}]:sum(),
              logp = beam_logprobs_sum_table[divm][vix]
            }
            if export_vis then
              final_beam['candidate'] = candidates_kept_for_divm[vix]
            end
            table.insert(done_beams_table[divm], final_beam)
          end
          -- don't continue beams from finished sequences
          if is_first_end_token then
            beam_logprobs_sum_table[divm][vix] = -1000
          end
        end

        -- move this group one step forward in time
        it = beam_seq_table[divm][t-divm+1]
        out = opt.gen_logprobs(it,state_table[divm])
        logprobs_table[divm] = out[#out]:clone()
        temp_state = {}
        for i=1,opt.state_size do table.insert(temp_state, out[i]) end
        state_table[divm] = beam_utils.clone_list(temp_state)
      end
    end
    if export_vis then
      table.insert(vis_iterations, vis_candidates)
    end
  end
  local function compare_beam(a,b) return a.logp > b.logp end
  for i =1,opt.M do
    table.sort(done_beams_table[i],compare_beam)
    done_beams_table[i] = table.slice(done_beams_table[i], 1, bdash, 1)
    if export_vis then
      for j = 1,#(done_beams_table[i]) do
        local beam = done_beams_table[i][j]
        beam.candidate.kept_forever = true
      end
    end
  end
  return done_beams_table
end

return beam_utils
