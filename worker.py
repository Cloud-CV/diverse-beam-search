from __future__ import absolute_import
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'div_rnn.settings')

from django.conf import settings
from demo.utils import log_to_terminal

import demo.constants as constants
import PyTorch
import PyTorchHelpers
import pika
import time
import yaml
import json
import traceback
import os

# Loading the VQA Model forever
DBSModel = PyTorchHelpers.load_lua_class(constants.DBS_LUA_PATH, 'DBSTorchModel')
DBSTorchModel = DBSModel(
    constants.DBS_CONFIG['model'],
    constants.DBS_CONFIG['batch_size'], 
    # constants.DBS_CONFIG['num_images'],
    constants.DBS_CONFIG['language_eval'], 
    constants.DBS_CONFIG['dump_images'],
    constants.DBS_CONFIG['dump_json'], 
    constants.DBS_CONFIG['dump_json_postfix'], 
    constants.DBS_CONFIG['dump_path'],
    constants.DBS_CONFIG['B'],
    constants.DBS_CONFIG['M'],
    constants.DBS_CONFIG['lambda'], 
    constants.DBS_CONFIG['divmode'], 
    constants.DBS_CONFIG['temperature'], 
    # constants.DBS_CONFIG['primetext'],
    constants.DBS_CONFIG['ngram_length'], 
    # constants.DBS_CONFIG['image_folder'], 
    constants.DBS_CONFIG['image_root'], 
    constants.DBS_CONFIG['input_h5'], 
    constants.DBS_CONFIG['input_json'], 
    constants.DBS_CONFIG['split'], 
    constants.DBS_CONFIG['coco_json'], 
    constants.DBS_CONFIG['backend'], 
    constants.DBS_CONFIG['id'], 
    constants.DBS_CONFIG['seed'], 
    constants.DBS_CONFIG['gpuid'],
    constants.DBS_CONFIG['div_vis_dir'],
)


connection = pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost'))

channel = connection.channel()

channel.queue_declare(queue='dbs_task_queue', durable=True)
print(' [*] Waiting for messages. To exit press CTRL+C')

def callback(ch, method, properties, body):
    try:
        print(" [x] Received %r" % body)
        body = yaml.safe_load(body) # using yaml instead of json.loads since that unicodes the string in value

        result = DBSTorchModel.predict(body['image_folder'], body['prefix'])
        log_to_terminal(body['socketid'], {"terminal": json.dumps(result)})
        log_to_terminal(body['socketid'], {"result": json.dumps(result)})
        log_to_terminal(body['socketid'], {"terminal": "Completed the Diverse Beam Search task"})

        ch.basic_ack(delivery_tag = method.delivery_tag)
    except Exception, err:
        log_to_terminal(body['socketid'], {"terminal": json.dumps({"Traceback": str(traceback.print_exc())})})

channel.basic_consume(callback,
                      queue='dbs_task_queue')

channel.start_consuming()
