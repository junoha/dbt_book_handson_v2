#!/bin/bash
set -e
ZIP_FILE=$1
if [ -z $ZIP_FILE ]; then
  echo "zip file is required"
  exit 1
fi

DEPLOYMENT=$(aws amplify create-deployment --app-id $AMPLIFY_APP_ID --branch-name $AMPLIFY_BRANCH_NAME)
JOB_ID=$(echo $DEPLOYMENT | jq -r '.jobId')
UPLOAD_URL=$(echo $DEPLOYMENT | jq -r '.zipUploadUrl')
curl -T "$ZIP_FILE" "$UPLOAD_URL"
aws amplify start-deployment --app-id $AMPLIFY_APP_ID --branch-name $AMPLIFY_BRANCH_NAME --job-id $JOB_ID

while true; do
  STATUS=$(aws amplify get-job --app-id $AMPLIFY_APP_ID --branch-name $AMPLIFY_BRANCH_NAME --job-id $JOB_ID --query 'job.summary.status' --output text)
  if [ "$STATUS" = "SUCCEED" ]; then
    echo "Deployed successfully"
    break
  elif [ "$STATUS" = "FAILED" ]; then
    exit 1
  fi
  sleep 10
done
