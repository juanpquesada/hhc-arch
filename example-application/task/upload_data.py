#
# hhc-arch/example-application/tasks/task-exampleapplication/upload_data.py
#
import boto3
import os
import requests
import time

# AWS credentials and some useful constant values
AWS_ACCESS_KEY_ID      = 'AWS_ACCESS_KEY_ID>'
AWS_SECRET_ACCESS_KEY  = '<AWS_SECRET_ACCESS_KEY>'
AWS_REGION             = 'us-east-1'
AWS_S3_BUCKET          = '<BUCKET>'
AWS_S3_SERVICE_URL     = 's3.amazonaws.com'

text = """
Task:
  epsilon = 0.01
  parametric_mesh = 'tangled-parametric.msh'
  physical_mesh   = 'tangled-physical.msh'
  num_tangled_nodes = coons(parametric_mesh, physical_mesh)
  num_nodes = (64+1) * (64+1)
  if Float(num_tangled_nodes)/num_nodes >= epsilon
    max_iter = 300
    num_tangled_nodes = laplacian(parametric_mesh, physical_mesh, epsilon, max_iter)
  end

"""
print(text)

# Get the S3 client
s3 = boto3.client(service_name='s3', region_name=AWS_REGION, aws_access_key_id=AWS_ACCESS_KEY_ID, aws_secret_access_key=AWS_SECRET_ACCESS_KEY)

# Upload the meshes
parametric_mesh = 'tangled-parametric.msh'
s3.upload_file(parametric_mesh, AWS_S3_BUCKET, parametric_mesh, ExtraArgs={'ACL': 'public-read'})

physical_mesh = 'tangled-physical.msh'
s3.upload_file(physical_mesh, AWS_S3_BUCKET, physical_mesh, ExtraArgs={'ACL': 'public-read'})

time.sleep(0.5)