git config --global user.email "johnathan.v@quali.com"
git config --global user.name "johnathanvidu"
cd $ENVIRONMENTS_PATH/scripts
chmod +x ./init.sh
./init.sh $1 $2 $3 $4
export COMMIT=$(git rev-parse HEAD)