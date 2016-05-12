from django.shortcuts import render
from django.http import Http404, HttpResponse

from utils import char_rnn_vis_data, neuraltalk2_vis_data

import json


def home(request, template_name='vis.html'):
    '''
        Home Page View
    '''
    return render(request, template_name,)


def beam_search(request, template_name='vis.html'):
    '''
    '''
    if request.method == "POST" or request.is_ajax():
        application = request.POST.get('app')

        data = {
            'B': request.POST.get('B', 12),
            'G': request.POST.get('G', 3),
            'T': request.POST.get('T', 0),
            'lmbda': request.POST.get('lmbda', 0.5),
            'ngram_length': request.POST.get('ngram_length', 0.5),
            'divmode': request.POST.get('divmode', 0),
            'prime': request.POST.get('prefix', ''),
        }

        if application == 'char-rnn':
            vis_data = char_rnn_vis_data(data)
        elif application == 'neuraltalk2':
            data['img_fname'] = request.POST.get('img_fname', None)
            vis_data = neuraltalk2_vis_data(data, request)

        # print json.dumps(vis_data)
        return HttpResponse(json.dumps(vis_data))
    else:
        return Http404("Please try again")
