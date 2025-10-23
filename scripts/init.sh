# Usage:
#   ./init.sh <branch_name> <app_folder> [key=value ...]
#
# Arguments:
#   <branch_name>      Name of the git branch to create.
#   <app_folder>       Name of the application folder to create.
#   [key=value ...]    One or more key-value pairs as inputs to render (e.g., env=prod region=us-east-1).
#

# 1. create the branch
# 2. create the "app" folder
# 3. render the inputs - every input after the git related inputs should be considered the inputs to render. inputs are n the format of key=value
# 4. commit and push the changes

set -e

# Check required env vars
if [[ -z "$TEMPLATES_PATH" || -z "$ENVIRONMENTS_PATH" ]]; then
	echo "TEMPLATES_PATH and ENVIRONMENTS_PATH environment variables must be set."
	exit 1
fi

# Check arguments
if [[ $# -lt 2 ]]; then
	echo "Usage: $0 <branch_name> <app_folder> [key=value ...]"
	exit 1
fi

BRANCH_NAME="$1"
APP_FOLDER="$2"
shift 2
INPUTS=("$@")

# Create new branch in ENVIRONMENTS_PATH
cd "$ENVIRONMENTS_PATH"
git checkout -b "$BRANCH_NAME"

# List of environment folders
ENV_FOLDERS=("environments/prod" "environments/stage")

# Prepare terragrunt inputs block
generate_terragrunt_inputs() {
	echo "locals {"
	for kv in "${INPUTS[@]}"; do
		key="${kv%%=*}"
		value="${kv#*=}"
		# If value is numeric or boolean, don't quote; else, quote
		if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
			echo "  $key = $value"
		else
			echo "  $key = \"$value\""
		fi
	done
	echo "}"
}

# Create app_folder in each environment folder and write terragrunt.hcl
for env_dir in "${ENV_FOLDERS[@]}"; do
	APP_PATH="$ENVIRONMENTS_PATH/$env_dir/$APP_FOLDER"
	mkdir -p "$APP_PATH"
	TG_FILE="$APP_PATH/app.hcl"
	generate_terragrunt_inputs > "$TG_FILE"
done

# Commit and push
git add .
git commit -m "Initialize $APP_FOLDER in $BRANCH_NAME with terragrunt inputs"
git push --set-upstream origin "$BRANCH_NAME"

