from django.conf import settings
from demo.utils import log_to_terminal

import os
import pika
import sys
import json


def dbs_captioning(prefix, image_folder, socketid):
    connection = pika.BlockingConnection(pika.ConnectionParameters(
            host='localhost'))
    channel = connection.channel()

    channel.queue_declare(queue='dbs_task_queue', durable=True)
    message = {
        'image_folder': image_folder + "/",
        'prefix': prefix,
        'socketid': socketid,
    }

    log_to_terminal(socketid, {"terminal": "Publishing job to DBS Queue"})
    channel.basic_publish(exchange='',
                      routing_key='dbs_task_queue',
                      body=json.dumps(message),
                      properties=pika.BasicProperties(
                         delivery_mode = 2, # make message persistent
                      ))

    print(" [x] Sent %r" % message)
    log_to_terminal(socketid, {"terminal": "Job published successfully"})
    connection.close()
