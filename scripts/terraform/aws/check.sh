#/bin/bash
set -e
#--------------------------------------------------------------
# recursive check
#--------------------------------------------------------------
terraform validate
for file in `find /workspace/ -name "main.tf" -type f`; do
    dir=`dirname $file`
    cd ${dir}
    pwd
    terraform init -backend=false
    tflint
    tfsec
done
