#!/usr/bin/env bash
WORKING_DIR=$(pwd)
DOWNLOAD_URL="https://github.com/TryGhost/Ghost/releases/download/2.1.1/Ghost-2.1.1.zip"
APP_NAME="ghost-blog-$(openssl rand -hex 6)"
declare -a TOOLS=("git" "heroku" "wget" "unzip")

# Color Prompt Configurations
RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'

function message() {
    message_text=$1
    echo -e "${GREEN}${message_text}${RESET}"
}

function error() {
    error_text=$1
    echo -e "${RED}${error_text}${RESET}"
}

function check_if_tools_exist() {
    for tool in "${TOOLS[@]}"; do
        if [ ! -x "$(command -v ${tool})" ]; then
            error "Error: Missing Tool: ${tool}"
            exit 1
        fi
    done
}

function clone_and_setup_repo() {
    destination=$1
    repository=$2

    if [ -d ${destination} ]; then
        if [ "$(ls -A ${destination})" ]; then
            error "Destination Directory: ${destination} is not Empty."
            exit 1
        fi
    else
        mkdir -p ${destination}
    fi
    cd ${destination}

    # Download Ghost Contents and Unzip then to a directory
    message "Setting-up Ghost Blog Repository"
    wget ${repository}
    unzip *.zip
    rm *.zip

    # Setup Git Repo for Heroku
    git init
    git add -A
    git commit -m "Initial Commit for Ghost Blog"
}

function fix_knex_migration_issue() {
    message "Fixing Knex Migration Issues"
    destination=$1
    cd ${destination}
    sed -i '' "s/separator: '__'/separator: '__', parseValues: true/g" core/server/config/index.js
    sed -i '' "s/return nconf;/nconf.set('server', {port: process.env.PORT}); return nconf;/" core/server/config/index.js
    git add .
    git commit -m "Fix Knex Migration Issue"
}

check_if_tools_exist

while getopts ":d:r:n:h" opt; do
  case ${opt} in
    d )
      WORKING_DIR=$OPTARG
      ;;
    r )
      DOWNLOAD_URL=$OPTARG
      ;;
    n )
      APP_NAME=$OPTARG
      ;;
    h )
      echo "Usage: $0 "
      echo "    -d  Destination Directory to Create the Blog Repo"
      echo "    -r  Link for the Git Release Zip file for Ghost"
      echo "    -n  Name to be used for the Heroku App"
      echo "    -h  Help Document"
      exit 0
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      exit 1
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      exit 1
      ;;
  esac
done

clone_and_setup_repo ${WORKING_DIR} ${DOWNLOAD_URL}
fix_knex_migration_issue ${WORKING_DIR}

cd ${WORKING_DIR}

message "Creating a New Heroku App with Name :${APP_NAME}"
heroku create ${APP_NAME}
git push heroku master

message "Creating a New Database for Heroku App"
heroku addons:create cleardb:ignite
CLEARDB_DATABASE_URL=$(heroku config:get CLEARDB_DATABASE_URL | sed "s/\/\//\!/g" | cut -d'!' -f2)

DATABSE_USER=$(echo ${CLEARDB_DATABASE_URL} | cut -d':' -f1)
DATABSE_PASSWORD=$(echo ${CLEARDB_DATABASE_URL} | cut -d':' -f2 | cut -d'@' -f1)
DATABSE_HOST=$(echo ${CLEARDB_DATABASE_URL} | cut -d':' -f2 | cut -d'@' -f2 | cut -d'/' -f1)
DATABSE_NAME=$(echo ${CLEARDB_DATABASE_URL} | cut -d':' -f2 | cut -d'@' -f2 | cut -d'/' -f2 | cut -d'?' -f1)

message "Updating Database Configuration Environment for Heroku App"
heroku config:set \
    database__connection__user=${DATABSE_USER} \
    database__connection__password=${DATABSE_PASSWORD} \
    database__connection__host=${DATABSE_HOST} \
    database__connection__database=${DATABSE_NAME}

message "Fixing Server Run Port for Heroku App"
heroku config:set database__pool__max=2
heroku run "knex-migrator init"
heroku config:set server__host=0.0.0.0
heroku config:set url=https://${APP_NAME}.herokuapp.com

echo "export server__port=\$PORT npm start" > .profile
git add .profile
git commit -m 'Add .profile'
git push heroku master

message "Successfully Finished Deploying Ghost Blog on Heroku"
