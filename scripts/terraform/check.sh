#/bin/bash
set -e
#--------------------------------------------------------------
# recursive check
#--------------------------------------------------------------
tfenv install
terraform validate
for file in `find /workspace/ -name "main.tf" -type f`; do
    dir=`dirname $file`
    cd ${dir}
    pwd
    tfenv install
    terraform init -backend=false
    tflint
    tfsec
done
