#!/usr/bin/env bash
# Dependencies

# Cloudinit inital setup
#  - echo '<%= s3_access_key_id %>' >> /root/.awssecret
#  - echo '<%= s3_secret_access_key %>' >> /root/.awssecret
#  - echo 's3_bucket: <%= s3_bucket -%>' > /etc/aws-s3.conf

# yaml config file on s3bucket in this format written out by cloudinit on build:-
# domain: xxx.xx.xx
# zone: xx
# ttl: 60

# iam user for access
#{
#  "Version": "2012-10-17",
#  "Statement": [
#    {
#      "Effect": "Allow",
#      "Action": [
#        "route53:ChangeResourceRecordSets",
#        "route53:GetChange",
#        "route53:GetHostedZone",
#        "route53:ListHostedZones",
#        "route53:ListResourceRecordSets"
#      ],
#      "Resource": [
#        "arn:aws:route53:::hostedzone/<zone>"
#      ]
#    },
#    {
#      "Effect": "Allow",
#      "Action": [
#        "s3:GetObject"
#      ],
#      "Resource": "arn:aws:s3:::<s3_bucket>"
#    }
#  ]
#}
#
# Timkay aws cli tool, tr, awk, curl

aws_s3_config="/etc/aws-s3.conf"
aws_route53_config="/etc/aws-route53.conf"
meta_url="http://169.254.169.254/latest/meta-data"
hostname=$(hostname)
curlopts="-s --max-time 5"
tkay_url="https://raw.githubusercontent.com/timkay/aws/master/aws"
tkay_path="/usr/bin/aws-perl"

fatal() { echo "FATAL: $@"; logger "FATAL: $@"; exit 3; }
info() { echo "INFO: $@"; logger "INFO: $@"; }

# Params: key yaml-file Return: variable using the keyname with value from the yaml
parse_yaml_to_variable() { value=$(grep $1 $2 | awk -F: '{print $2}'| tr -d [:space:] ) ; eval $1=\${value}; }

bootstrap_tim_kay_aws() {
  [ ! -x aws-perl ] && curl $curlopts $tkay_url -o $tkay_path && chmod +x $tkay_path || \
    fatal "Tim Kay aws Perl cli not availble at $tkay_path"
}

detect_aws_metadata() { curl $curlopts ${meta_url}/$1; }

pull_down_r53_config() {
  info pull_down_r53_config
  aws-perl get ${s3_bucket}/aws-route53.conf $aws_route53_config
  if [[ ! -r $aws_route53_config ]];then
    fatal "No $aws_route53_config"
  fi
}

read_s3_config() { parse_yaml_to_variable s3_bucket $aws_s3_config; }
read_route53_config() {
  parse_yaml_to_variable domain $aws_route53_config
  parse_yaml_to_variable zone $aws_route53_config
  parse_yaml_to_variable ttl $aws_route53_config
}

configure_dns_names() { internal_name="${hostname}-private.${domain}"; public_name="${hostname}.${domain}"; }

detect_dns_ip() { aws-perl lrrs $zone  --name=$1 | head -n10 | grep Value | tr -d '\t <Value>/ '; }

dns_transaction() {
  if [[ "$3" == "$2" ]];then
    info "Current dns $3 matches the aws allocation no action required"
  else
    info "Creating $1 A $2 dns record"
    aws-perl --fail crrs $zone --action DELETE --value $public_dns_ip --type A --name $public_name --ttl $ttl
    aws-perl crrs $zone --action CREATE --value $public_ip --type A --name $public_name --ttl $ttl
  fi
}

start_on_boot() {
  ! grep -q route53-dynamic_dns_update.sh /etc/rc.local &&  echo "/usr/local/bin/route53-dynamic_dns_update.sh" >> /etc/rc.local
}

bootstrap_tim_kay_aws
read_s3_config
pull_down_r53_config
read_route53_config
configure_dns_names
internal_ip=$(detect_aws_metadata local-ipv4)
public_ip=$(detect_aws_metadata public-ipv4)
internal_dns_ip=$(detect_dns_ip $internal_name)
public_dns_ip=$(detect_dns_ip $public_name)
dns_transaction $internal_name $internal_ip $internal_dns_ip
dns_transaction $public_name $public_ip $public_dns_ip
start_on_boot

