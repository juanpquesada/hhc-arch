#
# hhc-arch/example-application/procs/laplacian-azure/function_app.py
#
import azure.functions as func
import boto3
import json
import math
import requests

### CONSTANTS ###
# AWS
AWS_ACCESS_KEY_ID      = '<AWS_ACCESS_KEY_ID>'
AWS_SECRET_ACCESS_KEY  = '<AWS_SECRET_ACCESS_KEY>'
AWS_REGION             = 'us-east-1'
AWS_S3_BUCKET          = '<AWS_S3_BUCKET>'
AWS_S3_SERVICE_URL     = 's3.amazonaws.com'
AWS_SQS_RESPONSE_QUEUE = 'in-queue'

# Other useful constants
DEFAULT_EPSILON  = 0.01
DEFAULT_MAX_ITER = 300

app = func.FunctionApp()

### CLASSES ###
class Element:
  def __init__(self, id, type, num_tags, node_id_list):
    self.id           = id
    self.type         = type
    self.num_tags     = num_tags
    self.node_id_list = node_id_list

class Node:
  def __init__(self, id, x, y, z):
    self.id = id
    self.x  = x
    self.y  = y
    self.z  = z

class Position:  # Position of a node within the parametric grid
  def __init__(self, i, j):
    self.i = i
    self.j = j

class Vector:
  def __init__(self, x, y, z):
    self.x = x
    self.y = y
    self.z = z

### FUNCTIONS ###
# Function that generates the file with the optimized mesh
def gen_optimized_mesh(s3key, physical_grid, node_ordered_pos, elements):
  num_nodes = len(node_ordered_pos)
  num_elements = len(elements)

  f = "$MeshFormat\n"
  f += "2.2 0 8\n"
  f += "$EndMeshFormat\n"
  f += "$Nodes\n"
  f += str(num_nodes) + "\n"
  for k in range(num_nodes):
    # id x y z
    i = node_ordered_pos[k].i
    j = node_ordered_pos[k].j
    node = physical_grid[i][j]
    line = str(k+1) + " " + str(node.x) + " " + str(node.y) + " " + str(node.z) + "\n"
    f += line
  f += "$EndNodes\n"
  f += "$Elements\n"
  f += str(num_elements) + "\n"
  for i in range(num_elements):
    # id type num_tags node_id_list
    line = str(i+1) + " " + str(elements[i].type) + " " + str(elements[i].num_tags) + " " + str(elements[i].node_id_list[0]) + " " + str(elements[i].node_id_list[1]) + " " + str(elements[i].node_id_list[2]) + " " + str(elements[i].node_id_list[3]) + "\n"
    f += line
  f += "$EndElements"

  upload_object(AWS_S3_BUCKET, s3key, f, 'text/plain')

# Function that gets the boundary grid
def get_boundary(physicaldata_s3object_url, parametric_grid):
  nodes = get_mesh_nodes(physicaldata_s3object_url)
  boundary_grid = []
  num_nodes = len(nodes)
  if num_nodes == 0:
    return boundary_grid
  num_rows = int(math.sqrt(num_nodes))
  num_cols = num_rows

  for i in range(num_rows):
    boundary_grid.append([])
    for j in range(num_cols):
      boundary_grid[i].append(0)
  for i in range(num_rows):
    if i==0 or i==(num_rows-1):
      for j in range(num_cols):
        node = parametric_grid[i][j]
        boundary_grid[i][j] = nodes[node.id-1]
    else:
      node = parametric_grid[i][0]
      boundary_grid[i][0] = nodes[node.id-1]
      node = parametric_grid[i][num_cols-1]
      boundary_grid[i][num_cols-1] = nodes[node.id-1]

  return boundary_grid

# Function that gets the mesh nodes and elements
def get_mesh_data(mesh_s3object_url):
  try:
    f = requests.get(mesh_s3object_url).text
    lines = f.split("\n")
  except:
    return [], []

  # $MeshFormat
  # 2.2 0 8
  # $EndMeshFormat
  # $Nodes
  num_nodes = int(lines[4])
  nodes = []
  for i in range(num_nodes):
    line = lines[5+i]
    data = line.split()
    # id x y z
    node = Node(int(data[0]), float(data[1]), float(data[2]), float(data[3]))
    nodes.append(node)
  # $EndNodes
  # $Elements
  cur_line = 5 + num_nodes + 2
  num_elements = int(lines[cur_line])
  cur_line = cur_line + 1
  elements = []
  for i in range(num_elements):
    line = lines[cur_line+i]
    data = line.split()
    node_id_list = [int(data[3]), int(data[4]), int(data[5]), int(data[6])]
    # id type num_tags node_id_list
    element = Element(int(data[0]), int(data[1]), int(data[2]), node_id_list)
    elements.append(element)
  # $EndElements

  return nodes, elements

# Function that gets the mesh nodes
def get_mesh_nodes(mesh_s3object_url):
  try:
    f = requests.get(mesh_s3object_url).text
    lines = f.split("\n")
  except:
    return []

  # $MeshFormat
  # 2.2 0 8
  # $EndMeshFormat
  # $Nodes
  num_nodes = int(lines[4])
  nodes = []
  for i in range(num_nodes):
    line = lines[5+i]
    data = line.split()
    # id x y z
    node = Node(int(data[0]), float(data[1]), float(data[2]), float(data[3]))
    nodes.append(node)
  # $EndNodes
  # $Elements
  # ...
  # $EndElements

  return nodes

# Function that returns a node grid in parameter space and an array with the position of every node in that grid
def get_parametric_grid(nodes):
  num_nodes = len(nodes)
  num_rows = int(math.sqrt(num_nodes))
  num_cols = num_rows
  parametric_grid = []
  node_ordered_pos = []
  for i in range(num_rows):
    parametric_grid.append([])
    for j in range(num_cols):
      parametric_grid[i].append(0)
  for i in range(num_nodes):
    node_ordered_pos.append(0)

  for k in range(num_nodes):
    i = int((num_rows-1)*nodes[k].x)
    j = int((num_cols-1)*nodes[k].y)
    parametric_grid[i][j] = nodes[k]
    pos = Position(i, j)
    node_ordered_pos[k] = pos

  return parametric_grid, node_ordered_pos

# Laplacian Processing
def laplacian(laplacian_grid, m, n, epsilon, max_iter):
  num_nodes = (m+1) * (n+1)

  for k in range(max_iter):
    # Calculate coordinates of each point
    for i in range(1, m):
      for j in range(1, n):
        laplacian_grid[i][j].x = (laplacian_grid[i+1][j].x + laplacian_grid[i-1][j].x + laplacian_grid[i][j+1].x + laplacian_grid[i][j-1].x)/4
        laplacian_grid[i][j].y = (laplacian_grid[i+1][j].y + laplacian_grid[i-1][j].y + laplacian_grid[i][j+1].y + laplacian_grid[i][j-1].y)/4

    #Calculate number of tangled nodes
    #v1 = v2 = Vector(0.0, 0.0, 0.0)
    v1_x = v1_y = v2_x = v2_y = 0
    num_tangled_nodes = 0
    for i in range(1, m):
      for j in range(1, n):
        for T in range(1, 5):
          if T == 1:
            v1_x = laplacian_grid[i][j+1].x - laplacian_grid[i][j].x
            v1_y = laplacian_grid[i][j+1].y - laplacian_grid[i][j].y
            v2_x = laplacian_grid[i-1][j].x - laplacian_grid[i][j].x
            v2_y = laplacian_grid[i-1][j].y - laplacian_grid[i][j].y
          elif T == 2:
            v1_x = laplacian_grid[i-1][j].x - laplacian_grid[i][j].x
            v1_y = laplacian_grid[i-1][j].y - laplacian_grid[i][j].y
            v2_x = laplacian_grid[i][j-1].x - laplacian_grid[i][j].x
            v2_y = laplacian_grid[i][j-1].y - laplacian_grid[i][j].y
          elif T == 3:
            v1_x = laplacian_grid[i][j-1].x - laplacian_grid[i][j].x
            v1_y = laplacian_grid[i][j-1].y - laplacian_grid[i][j].y
            v2_x = laplacian_grid[i+1][j].x - laplacian_grid[i][j].x
            v2_y = laplacian_grid[i+1][j].y - laplacian_grid[i][j].y
          elif T == 4:
            v1_x = laplacian_grid[i+1][j].x - laplacian_grid[i][j].x
            v1_y = laplacian_grid[i+1][j].y - laplacian_grid[i][j].y
            v2_x = laplacian_grid[i][j+1].x - laplacian_grid[i][j].x
            v2_y = laplacian_grid[i][j+1].y - laplacian_grid[i][j].y
          if (v1_x*v2_y - v2_x*v1_y) <= 0:
            num_tangled_nodes += 1
            break
    if (float(num_tangled_nodes)/num_nodes) < epsilon:
      break

  return num_tangled_nodes
  
# Function that sends a process response message
def send_process_response_message(task_name, proc_id, proc_result):
  sqs = boto3.resource('sqs', region_name=AWS_REGION, aws_access_key_id=AWS_ACCESS_KEY_ID, aws_secret_access_key=AWS_SECRET_ACCESS_KEY)
  queue = sqs.get_queue_by_name(QueueName=AWS_SQS_RESPONSE_QUEUE)
  process_response_message = {
    'type': 'process-response',
    'response': {
      'taskName': task_name,
      'procId': proc_id,
      'result': proc_result
    }
  }
  json_message = json.dumps(process_response_message)
  resp = queue.send_message(MessageBody=json_message)

# Function that uploads an object to a S3 bucket
def upload_object(bucket_name, key, data, content_type, acl='public-read'):
  s3 = boto3.resource('s3', region_name=AWS_REGION, aws_access_key_id=AWS_ACCESS_KEY_ID, aws_secret_access_key=AWS_SECRET_ACCESS_KEY)
  bucket = s3.Bucket(bucket_name)
  bucket.put_object(ACL=acl, Body=data, ContentType=content_type, Key=key, Metadata={'topic': 'HHC-ARCH'})

@app.function_name(name="laplacian")
@app.queue_trigger(arg_name="msg", queue_name="laplacian-queue-azure",
                   connection="AzureWebJobsStorage") 
def main(msg: func.QueueMessage):
  message = json.loads(msg.get_body())
  message_type = message['type']
  if message_type == 'process-trigger':
    trigger = message['trigger']

    # Get the URLs of the S3 objects
    parametric_data_url = trigger['params']['parametricData']
    boundary_data_url = trigger['params']['boundaryData']

    # Read parametric data
    nodes, elements = get_mesh_data(parametric_data_url)
    num_nodes = len(nodes)
    num_elements = len(elements)
    parametric_grid, node_ordered_pos = get_parametric_grid(nodes)

    # Generate the optimized mesh in physical space:
    # Laplacian Processing
    laplacian_grid = get_boundary(boundary_data_url, parametric_grid)
    num_rows = int(math.sqrt(num_nodes))
    num_cols = num_rows
    for i in range(1, (num_rows-1)):
      for j in range(1, (num_cols-1)):
        laplacian_grid[i][j] = parametric_grid[i][j]
    epsilon  = DEFAULT_EPSILON
    max_iter = DEFAULT_MAX_ITER
    if 'epsilon' in trigger['params']:
      epsilon = eval(trigger['params']['epsilon'])
    if 'maxIter' in trigger['params']:
      max_iter = int(eval(trigger['params']['maxIter']))
    num_tangled_nodes = laplacian(laplacian_grid, num_rows-1, num_cols-1, epsilon, max_iter)
    key = 'laplacian-' + trigger['taskName'] + '-p' + str(trigger['procId']) + '.msh'
    gen_optimized_mesh(key, laplacian_grid, node_ordered_pos, elements)
    key_tangled_nodes = 'tanglednodes-' + trigger['taskName'] + '-p' + str(trigger['procId'])
    upload_object(AWS_S3_BUCKET, key_tangled_nodes, str(num_tangled_nodes), 'text/plain')
    result = {
      'mesh2D': 'http://' + AWS_S3_SERVICE_URL + '/' + AWS_S3_BUCKET + '/' + key,
      'numTangledNodes': 'http://' + AWS_S3_SERVICE_URL + '/' + AWS_S3_BUCKET + '/' + key_tangled_nodes
    }

    send_process_response_message(trigger['taskName'], trigger['procId'], result)
  """return {
      "statusCode": 200,
      "body": "Azure Function: laplacian"
  }"""
