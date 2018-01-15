#!/usr/bin/python -u
import argparse, logging
import common

parser = argparse.ArgumentParser(description='Create VM on Google Compute.')
parser.add_argument('name', metavar='NAME', type=str,
                    help='the name for the new VM')
args = parser.parse_args()
name = args.name

image_response = common.compute.images().getFromFamily(
        project=common.project, family='linuxkit-ci-builder').execute()
source_disk_image = image_response['selfLink']

logging.info("Using source disk image %s", source_disk_image)

config = {
        'name': name,
        'machineType': 'zones/europe-west1-b/machineTypes/custom-2-5120',
        'minCpuPlatform': 'Intel Haswell',
        'disks': [
            {
                'boot': True,
                'autoDelete': True,
                'initializeParams': {
                    'sourceImage': source_disk_image,
                    }
                }
            ],
        'networkInterfaces': [{
            'network': 'global/networks/default',
            'accessConfigs': [
                {'type': 'ONE_TO_ONE_NAT', 'name': 'External NAT'}
                ]
            }],
        'serviceAccounts': [{
            'email': 'default',
            'scopes': [
                ]
            }],
    }

logging.info("Creating VM")
resp = common.compute.instances().insert(body=config, project=common.project, zone=common.zone).execute()
common.wait_for_operation(operation = resp['name'])

logging.info("Getting VM details")
vm = common.compute.instances().get(project=common.project, zone=common.zone, instance=name).execute()

def get_nat_ip(item):
    net = item['networkInterfaces']
    for n in net:
        for access in n['accessConfigs']:
            ip = access['natIP']
            return ip
    raise Exception("No napIP in VM state: %r" % item)

print get_nat_ip(vm)

