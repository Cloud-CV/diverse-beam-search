from django.shortcuts import render
from django.conf import settings
from django.http import Http404, HttpResponse
from django.http import JsonResponse
from django.core.urlresolvers import reverse

from utils import char_rnn_vis_data, neuraltalk2_vis_data

import image_captioning.constants as constants
import random
import os

def char_rnn(request, template_name="char-rnn.html"):
    """
        Home view for char-rnn
    """
    return render(request, template_name,)


def neuraltalk2(request, template_name="neuraltalk2.html"):
    """
        Home view for neuraltalk2
    """
    demo_images_path = constants.DBS_DEMO_IMAGES_PATH
    demo_images = [random.choice(next(os.walk(demo_images_path))[2]) for i in range(6)]
    demo_images = [os.path.join(constants.DBS_DEMO_IMAGES_PATH, x) for x in demo_images]
    return render(request, template_name,{'demo_images': demo_images})


def beam_search(request, template_name='vis.html'):
    '''
        Business logic involved for both neuraltalk2 and char-rnn
    '''
    if request.method == "POST" or request.is_ajax():
        application = request.POST.get('app')
        # print application.split("/")[-1]
        data = {
            'B': request.POST.get('B', 12),
            'G': request.POST.get('G', 3),
            'T': request.POST.get('T', 0),
            'lmbda': request.POST.get('lmbda', 0.5),
            'ngram_length': request.POST.get('ngram_length', 0.5),
            'divmode': request.POST.get('divmode', 0),
            'prime': request.POST.get('prefix', ''),
        }
        if application == "char-rnn":
            vis_data = char_rnn_vis_data(data)
        elif application == "neuraltalk2":
            vis_data = neuraltalk2_vis_data(data, request)

        return JsonResponse(vis_data)
    else:
        return Http404("Please try again")
