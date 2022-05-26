#/bin/bash
set -e
#--------------------------------------------------------------
# recursive check
#--------------------------------------------------------------
tfenv install
terraform validate
for file in `find /workspace/ ! -path '*/.terraform/*' -type f -name 'main.tf'`; do
    dir=`dirname $file`
    cd ${dir}
    pwd
    tfenv install
    terraform init -backend=false
    tflint
    tfsec
done
