from django.conf import settings
import tempfile
import os
import glob
import shutil
import io
import tempfile
import subprocess
import json

img_map = {}


def char_rnn_vis_data(data):
    print "####### CHAR RNN function working ###########"
    data = dict(data)
    temp_file = tempfile.NamedTemporaryFile(delete=False)
    temp_file.close()
    data['fname'] = temp_file.name

    cmd = ('th stag_sample_gen.lua '
               '-B {B} -M {G} -T {T} '
               '-primetext "{prime}" '
               '-lambda {lmbda} '
               '-ngram_length {ngram_length} '
               '-divmode {divmode} '
               '-verbose 0 '
               '-jsondst {fname}'.format(**data))

    proc = subprocess.Popen(cmd, shell=True, cwd='../dbs/')
    proc.wait()
    if proc.returncode:
        raise Exception('Torch process failed')

    with open(temp_file.name, 'r') as f:
        vis_data = json.load(f)
    os.remove(temp_file.name)
    return vis_data


def neuraltalk2_vis_data(data, request):
    print "######  NeuralTalk working #######"
    data = dict(data)
    temp_dir_name = tempfile.mkdtemp()
    data['vis_dir'] = temp_dir_name

    # set up gallery for neuraltalk2
    data['gallery_dir'] = os.path.join(settings.BASE_DIR, 'media', 'vis', 'neuraltalk2')
    if not os.path.exists(data['gallery_dir']):
        os.makedirs(data['gallery_dir'])

    if 'img' in request.FILES:
        f = request.FILES.get('img')
        img_dst = os.path.join(data['gallery_dir'], f.filename)
        f.save(img_dst)
    else:
        assert 'img_fname' in data
        img_src = os.path.join(settings.BASE_DIR, 'media', 'vis', 'neuraltalk2', data['img_fname'])
        img_dst = os.path.join(data['gallery_dir'], data['img_fname'])
        # shutil.copyfile(img_src, img_dst)

    data['gpuid'] = settings.VIS_GPU_ID

    if data['gpuid'] >= 0:
        data['model'] = 'model_id1-501-1448236541.t7'
    else:
        data['model'] = 'model_id1-501-1448236541.t7_cpu.t7'

    cmd = ('th eval.lua '
            '-model {model} '
            '-image_folder "{gallery_dir}" '
            '-num_images 1 '
            '-B {B} -M {G} '
            '-lambda {lmbda} '
            '-ngram_length {ngram_length} '
            '-primetext "{prime}" '
            '-divmode {divmode} '
            '-gpuid {gpuid} '
            # these are for the vis that comes with neuraltalk2
            '-dump_images 0 -dump_json 0 '
            '-div_vis_dir "{vis_dir}"'.format(**data))

    proc = subprocess.Popen(cmd, shell=True, cwd='../application/image_captioning/code/')
    proc.wait()

    if proc.returncode:
        raise Exception('Torch process failed')

    with open(os.path.join(temp_dir_name, 'data.json'), 'r') as f:
        vis_data = json.load(f)

    # TODO: better way to do this?... not sanitized (check for /?)... not always unique?
    unique_name = os.path.split(temp_dir_name)[1] + '_' + data['img_fname']
    img_map[unique_name] = img_dst
    vis_data['img_url'] = os.path.join('/imgs/', unique_name)

    return vis_data
