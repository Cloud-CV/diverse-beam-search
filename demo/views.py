from django.shortcuts import render
from django.http import JsonResponse
from django.conf import settings
from channels import Group

from demo.sender import dbs_captioning
from demo.utils import log_to_terminal

import demo.constants as constants
import uuid
import os
import random
import traceback
import urllib2
import shutil


def home(request, template_name="index.html"):
    return render(request, template_name,)


def captioning(request, template_name="dbs.html"):
    socketid = uuid.uuid4()
    if request.method == "POST":
        try:
            image_folder = request.POST.get('image_folder')
            image_folder = urllib2.unquote(image_folder)
            prefix = request.POST.get('prefix', '')
            socketid = request.POST.get('socketid')
            demoType = request.POST.get("demoType")

            if demoType == "demoImage":
                image_path = os.path.join(settings.BASE_DIR, str(image_folder)[1:])
                random_uuid = uuid.uuid1()
                # place the demo image in a new folder as a new job
                output_dir = os.path.join(settings.MEDIA_ROOT, 'images', str(random_uuid))

                if not os.path.exists(output_dir):
                    os.makedirs(output_dir)

                print image_path, output_dir
                shutil.copy(image_path, output_dir)
                image_folder = output_dir

            log_to_terminal(socketid, {"terminal": "Starting Diverse Beam Search Job..."})
            response = dbs_captioning(prefix, image_folder, socketid)
        except Exception, err:
            log_to_terminal(socketid, {"terminal": traceback.print_exc()})

    demo_images = get_demo_images(constants.COCO_IMAGES_PATH)
    return render(request, template_name, {"demo_images": demo_images, 'socketid': socketid})


def file_upload(request):
    if request.method == "POST":
        image = request.FILES['file']

        random_uuid = uuid.uuid1()
        # handle image upload
        output_dir = os.path.join(settings.MEDIA_ROOT, 'images', str(random_uuid))

        if not os.path.exists(output_dir):
            os.makedirs(output_dir)

        img_path = os.path.join(output_dir, str(image))
        handle_uploaded_file(image, img_path)

        return JsonResponse({"file_path": img_path.replace(settings.BASE_DIR, ""), "image_folder": output_dir})    


def handle_uploaded_file(f, path):
    with open(path, 'wb+') as destination:
        for chunk in f.chunks():
            destination.write(chunk)


def get_demo_images(demo_images_path):
    try:
        images_list = next(os.walk(demo_images_path))[2]
        demo_images = select_random_six_demo_images(images_list)

        demo_images = [os.path.join(settings.MEDIA_URL, 'coco', 'val2014', x) for x in demo_images]
    except:
        images = ['img1.jpg', 'img2.jpg', 'img3.jpg', 'img4.jpg', 'img5.jpg', 'img6.jpg', ]
        demo_images = [os.path.join(settings.STATIC_URL, 'images', x) for x in images]
    return demo_images


def select_random_six_demo_images(images_list):
    prefixes = ('classify', 'vqa', 'captioning')
    demo_images = [random.choice(images_list) for i in range(6)]
    for i in demo_images[:]:
        if i.startswith(prefixes):
            demo_images = select_random_six_demo_images(images_list)
    return demo_images
