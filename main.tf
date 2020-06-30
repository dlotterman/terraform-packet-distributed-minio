provider "packet" {
    auth_token = var.auth_token
}

resource "random_string" "minio_access_key" {
    length = 20
    min_upper = 1
    min_lower = 1
    min_numeric = 1
    special = false
}

resource "random_string" "minio_secret_key" {
    length = 40
    min_upper = 1
    min_lower = 1
    min_numeric = 1
    special = false
}

data "template_file" "user_data" { 
    template = file("${path.module}/templates/user_data.sh")
    vars = {
        minio_access_key = random_string.minio_access_key.result
        minio_secret_key = random_string.minio_secret_key.result
        minio_node_count = var.node_amount
        minio_drive_model = var.storage_drive_model
   }
}

resource "packet_device" "minio-distributed-cluster" {
    count = var.node_amount
    project_id = var.project_id
    hostname = "${format("%s%d",var.hostname, count.index+1)}" 
    plan = var.plan
    facilities = [var.facility]
    operating_system = var.operating_system
    billing_cycle = var.billing_cycle
}

# Bash command to populate /etc/hosts file on each instances
resource "null_resource" "provision_cluster_member_hosts_file" {
  count = var.node_amount

  # Changes to any instance of the cluster requires re-provisioning
  triggers = {
    cluster_instance_ids = "${join(",", packet_device.minio-distributed-cluster.*.id)}"
  }
  connection {
    type = "ssh"
    user = "root"
    host = "${element(packet_device.minio-distributed-cluster.*.access_public_ipv4, count.index)}"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "file" {
    content     = data.template_file.user_data.rendered
    destination = "/tmp/setup-minio-distributed.sh"
  }

  provisioner "remote-exec" {
    inline = [
      # Adds all cluster members' IP addresses to /etc/hosts (on each member)
      "echo '${join("\n", formatlist("%v", packet_device.minio-distributed-cluster.*.access_public_ipv4))}' | awk 'BEGIN{ print \"\\n\\n# Minio Distributed Cluster members:\" }; { print $0 \" ${var.hostname}\" NR }' | sudo tee -a /etc/hosts > /dev/null",
      "chmod +x /tmp/setup-minio-distributed.sh",
      "/tmp/setup-minio-distributed.sh"
    ]
  }

 # provisioner "remote-exec" {
 #   when = "destroy"
 #   inline = [
 #     "head -n -${var.node_amount+3} /etc/hosts > /tmp/tmp_file && mv -f /tmp/tmp_file /etc/hosts"
 #   ]
 # }
}
