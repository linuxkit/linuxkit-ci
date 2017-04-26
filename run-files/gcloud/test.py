#!/usr/bin/python -u
import argparse, logging, os, time, json, sys
from googleapiclient.errors import HttpError
import common

from google.cloud import storage
from google.auth.credentials import Credentials

parser = argparse.ArgumentParser(description='Upload a file to our bucket')
parser.add_argument('src', metavar='SRC', type=str, help='the path of the local file to upload')
parser.add_argument('name', metavar='NAME', type=str, help='the name for the new VM instance')
args = parser.parse_args()

source_file_name = args.src
destination_blob_name = args.name + '.tar.gz'

logging.info("Connecting to storage")

storage_client = storage.Client(project = common.project)

bucket_name = os.environ['CLOUDSDK_IMAGE_BUCKET']

logging.info("Getting bucket")
bucket = storage_client.get_bucket(bucket_name)
blob = bucket.blob(destination_blob_name)

logging.info("Uploading %s -> %s", source_file_name, destination_blob_name)

blob.upload_from_filename(source_file_name)

image_name = args.name + '-test-image'
body = {
    'name': image_name,
    'rawDisk': {
        'source': blob.self_link,
    },
}

image_link = None

if image_link is None:
    logging.info("Removing old image")
    try:
        image_response = common.compute.images().delete(project=common.project, image = image_name).execute()
        common.wait_for_global_operation(operation = image_response['name'])
    except Exception, ex:
        logging.info("Removal failed; assuming image didn't exist: %s", ex)

    logging.info("Creating image: %s", body)
    image_response = common.compute.images().insert(project=common.project, body=body).execute()
    image_link = image_response['targetLink']
    common.wait_for_global_operation(operation = image_response['name'])

config = {
        'name': args.name,
        'machineType': 'zones/europe-west1-b/machineTypes/n1-standard-1',
        'disks': [
            {
                'boot': True,
                'autoDelete': True,
                'initializeParams': {
                    'sourceImage': image_link,
                    }
                }
            ],
        'scheduling': {
            'preemptible': False,
            'onHostMaintenance': 'TERMINATE',
            'automaticRestart': False,
        },
        'networkInterfaces': [{ # Or you get "At least one network interface is required."
            'network': 'global/networks/default',
            'accessConfigs': [
                {'type': 'ONE_TO_ONE_NAT', 'name': 'External NAT'}
                ]
            }],
        'serviceAccounts': [],
        'metadata': [ {"serial-port-enable": True} ],
    }

logging.info("Creating VM")
resp = common.compute.instances().insert(body=config, project=common.project, zone=common.zone).execute()

# Don't wait for operation to complete!
# A headstart is needed as by the time we've polled for this event to be
# completed, the instance may have already terminated.

start=0
was_ready = False
while True:
    try:
        out = common.compute.instances().getSerialPortOutput(instance=config['name'], project=common.project, zone=common.zone, start=start).execute()
    except HttpError, ex:
        code = int(ex.resp['status'])
        if code == 404: break
        error = json.loads(ex.content)['error']
        reason = error['errors'][0]['reason']
        logging.info("Error getting serial output (%s): %s", reason, error['message'])
        if reason == 'resourceNotReady' and was_ready: break
        time.sleep(1)
    else:
        was_ready = True
        sys.stdout.write(out['contents'])
        sys.stdout.flush()
        start=int(out['next'])

