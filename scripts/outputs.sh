git config --global user.email "johnathan.v@quali.com"
git config --global user.name "johnathanvidu"
cd $ENVIRONMENTS_PATH/scripts
chmod +x ./init.sh
./init.sh {{ .inputs.app_name }}-dev {{ .inputs.app_name }} engine_version={{ .inputs.engine_version }} skip_final_version={{ .inputs.skip_final_version }}
export COMMIT=$(git rev-parse HEAD)