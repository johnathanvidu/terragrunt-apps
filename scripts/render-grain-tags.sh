
#!/bin/bash

# Usage: ./render-grain.sh <branch_name> <asset_folder> <app_folder>
#
# Arguments:
#   branch_name   - The git branch to switch to in the environments repo.
#   asset_folder  - The name of the asset folder inside the template path to copy.
#   app_folder    - The name of the app folder to create under each environment (prod, stage).
#
# Environment Variables:
#   ENVIRONMENTS_PATH - Path to the environments directory (must exist).
#   TEMPLATES_PATH     - Path to the templates directory (must exist).
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
BLUEPRINT_NAME="$4"

if [ -z "$ENVIRONMENTS_PATH" ] || [ -z "$TEMPLATES_PATH" ]; then
	echo "ENVIRONMENTS_PATH and TEMPLATES_PATH must be set as environment variables."
	exit 1
fi

cd "$ENVIRONMENTS_PATH"

# Checkout the branch, create if it doesn't exist
git fetch origin
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
	git checkout "$BRANCH_NAME"
else
	git checkout -b "$BRANCH_NAME" origin/"$BRANCH_NAME" || git checkout -b "$BRANCH_NAME"
fi

for ENV in prod stage; do
    
	ENV_DIR="$ENVIRONMENTS_PATH/environments/$ENV"
	APP_DIR="$ENV_DIR/$APP_FOLDER"
	mkdir -p "$APP_DIR"
    echo "copying folder $TEMPLATES_PATH/$ASSET_FOLDER/* to $APP_DIR/"
	cp -R "$TEMPLATES_PATH/$ASSET_FOLDER" "$APP_DIR/"
done

git add .
COMMIT_MSG="Add/update $ASSET_FOLDER to $APP_FOLDER in all environments [$(date)]"

# Retry loop for commit & push to handle race conditions
MAX_RETRIES=5
COUNT=0
if git commit -m "$COMMIT_MSG"; then
	while [ $COUNT -lt $MAX_RETRIES ]; do
		    git tag -a $BLUEPRINT_NAME $(git rev-parse HEAD) -m "Tagging commit for $BLUEPRINT_NAME"
			if git push origin --follow-tags "$BRANCH_NAME"; then # can use git push --atomic origin <branch name> <tag> instead if using git with https
				echo "Changes pushed successfully."
				exit 0
			else
				sleep 2
				echo "Push failed, attempting to rebase and retry ($((COUNT+1))/$MAX_RETRIES)..."
				git tag -d $BLUEPRINT_NAME
				git pull --rebase origin "$BRANCH_NAME"
			fi

		COUNT=$((COUNT+1))
	done
else
	echo "Nothing to commit, exiting."
	exit 0
fi

echo "Failed to push changes after $MAX_RETRIES attempts."
exit 1