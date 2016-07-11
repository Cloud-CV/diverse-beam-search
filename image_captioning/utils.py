from django.conf import settings
from django.core.files.storage import default_storage

import image_captioning.constants as constants

import glob
import io
import json
import os
import shutil
import subprocess
import tempfile


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
    # NOTE: The demo images should reside in the static/images/vis/neuraltalk2
    data = dict(data)
    temp_dir_name = tempfile.mkdtemp()
    data['vis_dir'] = temp_dir_name
    data['gallery_dir'] = os.path.join(settings.BASE_DIR, 'media', 'vis', 'neuraltalk2')
    if not os.path.exists(data['gallery_dir']):
        os.makedirs(data['gallery_dir'])

    # handle the case when user uploads his own image
    if request.POST.get('demo_method') == "usingOwnImage":
        if 'img' in request.FILES:
            f = request.FILES.get('img')
            img_dst = os.path.join(data['gallery_dir'], f.name)

            with open(default_storage.path(img_dst), 'wb+') as destination:
                    for chunk in f.chunks():
                        destination.write(chunk)
            img_path = os.path.join('media', 'vis', 'neuraltalk2', f.name)
            # stores the image path that needs to be rendered at the client side

    # handling the case when a demo image is submitted
    elif request.POST.get('demo_method') == "usingDemoImage":
        print request.POST.get('demo_image_path')
        img_path = request.POST.get("demo_image_path")

    data['gpuid'] = constants.VIS_GPU_ID

    if data['gpuid'] >= 0:
        data['model'] = 'model_id1-501-1448236541.t7'
    else:
        data['model'] = 'model_id1-501-1448236541.t7_cpu.t7'

    # print "THE DATA IS ", data

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

    vis_data['img_url'] = img_path

    return vis_data
