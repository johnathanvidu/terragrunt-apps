
#!/bin/bash

# Usage: ./render-grain.sh <branch_name> <asset_folder> <app_folder>
#
# Arguments:
#   branch_name   - The git branch to switch to in the environments repo.
#   asset_folder  - The name of the asset folder inside the template path to copy.
#   app_folder    - The name of the app folder to create under each environment (prod, stage).
#
# Environment Variables:
#   ENVIRONMNETS_PATH - Path to the environments directory (must exist).
#   TEMPLATE_PATH     - Path to the templates directory (must exist).
#
# Description:
#   - Switches to the specified branch in the environments repo.
#   - Copies the specified asset folder from the template path into a new app folder under each environment (prod, stage).
#   - Commits and pushes the changes, handling possible git conflicts due to concurrent script runs.

set -e

if [ "$#" -ne 3 ]; then
	echo "Usage: $0 <branch_name> <asset_folder> <app_folder>"
	exit 1
fi

BRANCH_NAME="$1"
ASSET_FOLDER="$2"
APP_FOLDER="$3"

if [ -z "$ENVIRONMNETS_PATH" ] || [ -z "$TEMPLATE_PATH" ]; then
	echo "ENVIRONMNETS_PATH and TEMPLATE_PATH must be set as environment variables."
	exit 1
fi

cd "$ENVIRONMNETS_PATH"

# Checkout the branch, create if it doesn't exist
git fetch origin
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
	git checkout "$BRANCH_NAME"
else
	git checkout -b "$BRANCH_NAME" origin/"$BRANCH_NAME" || git checkout -b "$BRANCH_NAME"
fi

for ENV in prod stage; do
	ENV_DIR="$ENVIRONMNETS_PATH/$ENV"
	APP_DIR="$ENV_DIR/$APP_FOLDER"
	mkdir -p "$APP_DIR"
	cp -R "$TEMPLATE_PATH/$ASSET_FOLDER/." "$APP_DIR/"
done

git add .
COMMIT_MSG="Add/update $ASSET_FOLDER to $APP_FOLDER in all environments [$(date)]"

# Retry loop for commit & push to handle race conditions
MAX_RETRIES=5
COUNT=0
while [ $COUNT -lt $MAX_RETRIES ]; do
	if git commit -m "$COMMIT_MSG"; then
		if git push origin "$BRANCH_NAME"; then
			echo "Changes pushed successfully."
			exit 0
		else
			echo "Push failed, attempting to rebase and retry ($((COUNT+1))/$MAX_RETRIES)..."
			git pull --rebase origin "$BRANCH_NAME"
		fi
	else
		echo "Nothing to commit, exiting."
		exit 0
	fi
	COUNT=$((COUNT+1))
	sleep 2
done

echo "Failed to push changes after $MAX_RETRIES attempts."
exit 1