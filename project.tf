/*_____________________________________START______________________________*/

  provider "aws" {
  region     = "ap-south-1"
  profile    = "sulekhakey"
}


/*________ create a new key pair___________ 1.*/

resource "tls_private_key" "key" {
  algorithm = "RSA"
}

  module "key_pair" {

   source = "terraform-aws-modules/key-pair/aws"
    key_name   = "key123"
    public_key = tls_private_key.key.public_key_openssh
}



/*_________ create security group ____________2. */


resource "aws_security_group" "web-security" {

  depends_on = [
    tls_private_key.key,
  ]

  name = "web-security"
  description = "Web Security Group"

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

 ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}




/*____________ launch instance and install softwares ___________3.*/

resource "aws_instance" "myinstance" {

  depends_on = [
    aws_security_group.web-security,
  ]

  ami = "ami-0447a12f28fddb066"

  instance_type = "t2.micro"

  key_name = "key123"

  security_groups = [ "web-security" ]

    connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key =  tls_private_key.key.private_key_pem
    host     = aws_instance.myinstance.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
  tags = {
         Name = "instance1"
 }

}


/*_____________ create a ebs volume ________ 4.*/


resource "aws_ebs_volume" "ebs" {
   
   depends_on = [
    aws_instance.myinstance,
  ]


  availability_zone = aws_instance.myinstance.availability_zone
  size              = 1

  tags = {
    Name = "myebs"
  }
}

/*_______________ attach ebs volume to instances ________ 5.*/

resource "aws_volume_attachment" "ebs_attach" {

   depends_on = [
    aws_ebs_volume.ebs,
  ]

  device_name = "/dev/sdd"
  volume_id   = aws_ebs_volume.ebs.id
  instance_id = aws_instance.myinstance.id
  force_detach = true
}


/*___________ mount ebs volume to /var/www/html ___________6.*/


resource "null_resource" "nullremote1"  {

 depends_on = [
    aws_volume_attachment.ebs_attach,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.key.private_key_pem
    host     = aws_instance.myinstance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdd",
      "sudo mount  /dev/xvdd  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone  https://github.com/Sulekha02112001/terra.git  /var/www/html/"
    ]
  }
}


/*________________ create a s3 bucket and upload images _____________7.*/


resource "aws_s3_bucket" "mybucket" {

   depends_on = [
    null_resource.nullremote1,
  ]
    bucket  = "sulekha123"
    acl = "private"
    force_destroy = true


provisioner "local-exec" {
        command     = "git clone https://github.com/Sulekha02112001/terra.git    image-folder"
    }

   provisioner "local-exec" {
        when        =   destroy
        command     =   "echo Y | rmdir /s image-folder"
    }

}
resource "aws_s3_bucket_object" "image-upload" {
    bucket  = aws_s3_bucket.mybucket.bucket
    key     = "terraform.png"
    source  = "image-folder/terraform.png"
    acl = "public-read"
}


/*______________ create a cloudfront______________8.*/


locals {
  s3_origin_id = "aws_s3_bucket.mybucket.id"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.mybucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id


  }
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "terraform.png"

  logging_config {
    include_cookies = false
    bucket          =  aws_s3_bucket.mybucket.bucket_domain_name

  }


  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE","IN"]
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
 



/*____________________ deploy cloud front url in website _________________9.*/

output "out3" {

  value = aws_cloudfront_distribution.s3_distribution.domain_name

}

resource "null_resource" "nullremote2"  {

depends_on = [

     aws_cloudfront_distribution.s3_distribution,
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.key.private_key_pem
    host     = aws_instance.myinstance.public_ip
  }

provisioner "remote-exec" {
  inline = [
   "sudo su << EOF",
   "echo \"<img src='https://${aws_cloudfront_distribution.s3_distribution.domain_name}/terraform.png'  width='400' lenght='500' >\" >> /var/www/html/sulekha.html",
   "EOF"
  ]
}
}

/*______________________ start chrome and access  the website __________________________ 10.*/


resource "null_resource" "nulllocal1"  {

  depends_on = [
    null_resource.nullremote2,
  ]

	provisioner "local-exec" {
	    command = " start chrome  ${aws_instance.myinstance.public_ip}/sulekha.html"
  	}
}


/*_____________________________________FINISH____________________________________________*/