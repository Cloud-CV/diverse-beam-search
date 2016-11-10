from django.conf import settings
import os


COCO_IMAGES_PATH = os.path.join(settings.MEDIA_ROOT, 'coco', 'val2014')

DBS_CONFIG = {
    'model': 'models/model_id1-501-1448236541.t7_cpu.t7', 
    'batch_size': 1, 
    'num_images': 1, 
    'language_eval': 0,
    'dump_images': 1, 
    'dump_json': 1, 
    'dump_json_postfix': "", 
    'dump_path': 0, 
    'B': 2, 
    'M': 2, 
    'lambda': 0.1, 
    'divmode': 0, 
    'temperature': 1.0, 
    'primetext': "", 
    'ngram_length': 1, 
    'image_folder': "", 
    'image_root': "", 
    'input_h5': "", 
    'input_json': "", 
    'split': "test", 
    'coco_json': "", 
    'backend': "cudnn", 
    'id': "evalscript", 
    'seed': 123, 
    'div_vis_dir': str(os.path.join(settings.MEDIA_ROOT, 'div_vis_dir')),
}

DBS_GPUID = -1

if DBS_GPUID == -1:
    DBS_CONFIG['model'] = 'models/model_id1-501-1448236541.t7_cpu.t7'
    DBS_CONFIG['backend'] = "nn"
else:
    DBS_CONFIG['model'] = 'models/model_id1-501-1448236541.t7'
    DBS_CONFIG['backend'] = "cudnn"

DBS_LUA_PATH = "eval.lua"
