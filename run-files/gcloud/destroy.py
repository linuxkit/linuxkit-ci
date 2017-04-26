#!/usr/bin/python -u
import argparse, logging
import common

parser = argparse.ArgumentParser(description='Destroy a VM on Google Compute.')
parser.add_argument('name', metavar='NAME', type=str,
                    help='the name of the VM to be destroyed')
args = parser.parse_args()
name = args.name

logging.info("Destroying VM")
resp = common.compute.instances().delete(instance=name, project=common.project, zone=common.zone).execute()
common.wait_for_operation(operation = resp['name'])
