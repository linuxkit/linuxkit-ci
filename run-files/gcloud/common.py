#!/usr/bin/python
import time, logging, os
from oauth2client.service_account import ServiceAccountCredentials
from apiclient.discovery import build

logging.basicConfig()
logging.getLogger().setLevel(logging.INFO)
logging.getLogger('googleapiclient.discovery_cache').setLevel(logging.ERROR)
logging.getLogger('googleapiclient.discovery').setLevel(logging.WARNING)

project = os.environ["CLOUDSDK_CORE_PROJECT"]
zone = os.environ["CLOUDSDK_COMPUTE_ZONE"]
key_file = os.environ["CLOUDSDK_COMPUTE_KEYS"]

os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = key_file  # For storage library
credentials = ServiceAccountCredentials.from_json_keyfile_name(key_file)
compute = build('compute', 'v1', credentials=credentials)

def wait_for_operation(operation):
    logging.info('Waiting for zone operation to finish')
    while True:
        result = compute.zoneOperations().get(
            project=project,
            zone=zone,
            operation=operation).execute()

        if result['status'] == 'DONE':
            if 'error' in result:
                raise Exception(result['error'])
            return result
        logging.info("Operation in progress... waiting...")
        time.sleep(5)

def wait_for_global_operation(operation):
    logging.info('Waiting for global operation to finish')
    while True:
        result = compute.globalOperations().get(
            project=project,
            operation=operation).execute()

        if result['status'] == 'DONE':
            if 'error' in result:
                raise Exception(result['error'])
            return result
        logging.info("Operation in progress... waiting...")
        time.sleep(5)
