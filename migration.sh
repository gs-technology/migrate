#!/bin/bash -ex
# command for migration  docker run -v ~/databases:/databases migration_container {mysql|mongo|clickhouse}  
# command for fixing  docker run -v ~/databases:/databases migration_container {mysql|mongo|clickhouse} fix db_name fix_version
# Checking if the Database variable is empty or not correct value
if [[ ! $1 =~ ^(mysql|mongo|clickhouse)$ ]]; then
    echo "Database variable isn't set" && exit 1
fi

#Getting DB URL 
get_connector(){
  echo $keyName
  if [ -f /conf/creds/access_password ] && [ -f /conf/creds/access_username ]; then
     credsPass=$(cat /conf/creds/access_password)
     credsPass=$(echo -n "$credsPass" | base64 -D)
     credsUser=$(cat /conf/creds/access_username)
     credsPass=$(echo -n "$credsPass" | base64 -D)
     confSrvCreds=$(echo -n "{$credsUser}:${credsPass}" | base64 )
  fi

  #RES=$(gcurl -s $confsrvDomain/$confsrvPrefix/$keyName | jq -re '.properties | .[].value' || curl -s $confsrvDomain/$confsrvDefaultPrefix/$keyName | jq -re '.properties | .[].value')
  RES=$(grpcurl  -plaintext -d "{\"application\": \"all\", \"profile\": \"all\", \"label\": \"devops\", \"key\": \"${keyName}\"}"\
   -H "Authorization:Basic $confSrvCreds"\
   $confsrvDomain PropertiesService/GetPropertiesForKey |\
   jq -re '.properties | .[].value')
  echo $RES
  DB_URL=$(echo -n $RES | base64 -d)
}
#Migration Functions
mysql_migration () {
    echo "Migrating MYSQL databases"
    if [ ! -d "/databases/mysql" ]; then
    echo "mysql dir doesn't exists" && exit 1 # Checking if mysql dir exists
    fi
      DATABASES=`ls /databases/mysql/` # Getting databases 
      get_connector  # Getting Mysql connection URL
      for DB in ${DATABASES[@]}; do
          #Checking if previous upgrade was successfull
          if [ "$(ls -A /databases/mysql/$DB )" ] && [ -d "/databases/mysql/$DB" ]; then
              dirty=$(migrate -database ${DB_URL}$DB?x-no-lock=true -path /databases/mysql/$DB version 2>&1|awk -F'[ ]' '{print $2}')
              version=$(migrate -database ${DB_URL}$DB?x-no-lock=true -path /databases/mysql/$DB version 2>&1|awk -F'[ ]' '{print $1}')
              if [[ $dirty == "(dirty)" ]]; then
                if [ $version -le 1 ]; then
                   target_version=1
                else
                   target_version=$((version-=1))
                fi
                echo "Rolback migration to version $target_version"
                migrate -database ${DB_URL}$DB?x-no-lock=true -path /databases/mysql/$DB force $target_version
                echo "Migration after rolback for $DB database"
                migrate -database ${DB_URL}$DB?x-no-lock=true -path /databases/mysql/$DB up 
              else 
                echo "Migration for $DB database"
                migrate -database ${DB_URL}$DB?x-no-lock=true -path /databases/mysql/$DB up # Start Migration
              fi
          else
              echo "$DB is Empty or not a dir"
          fi
      done
}

mongo_migration () {
    echo "Migrating MONGO databases"
    if [ ! -d "/databases/mongo" ]; then
    echo "mongo dir doesn't exists" && exit 1 # Checking if mongo dir exists
    fi
      DATABASES=`ls /databases/mongo/` # Getting databases
      get_connector  # Getting Mongo connection URL
      for DB in ${DATABASES[@]}; do
          if [ "$(ls -A /databases/mongo/$DB )" ] && [ -d "/databases/mongo/$DB" ]; then
              dirty=$(migrate -database ${DB_URL}$DB -path /databases/mongo/$DB version 2>&1|awk -F'[ ]' '{print $2}')
              version=$(migrate -database ${DB_URL}$DB -path /databases/mongo/$DB version 2>&1|awk -F'[ ]' '{print $1}')
              if [[ $dirty == "(dirty)" ]]; then
                if [ $version -le 1 ]; then
                   target_version=1
                else
                   target_version=$((version-=1))
                fi
                echo "Rolback migration to version $target_version"
                migrate -database ${DB_URL}$DB -path /databases/mongo/$DB force $target_version
                echo "Migration after rolback in $DB database"
                migrate -database ${DB_URL}$DB -path /databases/mongo/$DB up 
              else 
              echo "Migration in $DB database"
              migrate -database ${DB_URL}$DB -path /databases/mongo/$DB up # Start Migration
              fi
          else
              echo "$DB is Empty or not dir"
          fi
      done
}

clickhouse_migration () {
    echo "Migrating CLICKHOUSE databases"
    if [ ! -d "/databases/clickhouse" ]; then
    echo "clickhouse dir doesn't exists" && exit 1 # Checking if clickhouse dir exists
    fi
      get_connector  # Getting Clickhouse connection URL
        if [ -z "$DB_URL" ]; then
          echo "There is no connection string, maybe its prod" && exit 1 # temporary fix for prod
          fi
          if [ "$(ls -A /databases/clickhouse/ )" ] && [ -d "/databases/clickhouse/" ]; then
              dirty=$(migrate -database ${DB_URL} -path /databases/clickhouse/ version 2>&1|awk -F'[ ]' '{print $2}')
              version=$(migrate -database ${DB_URL} -path /databases/clickhouse/ version 2>&1|awk -F'[ ]' '{print $1}')
              if [[ $dirty == "(dirty)" ]]; then
                if [ $version -le 1 ]; then
                   target_version=1
                else
                   target_version=$((version-=1))
                fi
                echo "Rolback migration to version $target_version"
                migrate -database ${DB_URL} -path /databases/clickhouse/ force $target_version
                echo "Migration after rolback"
                migrate -database ${DB_URL} -path /databases/clickhouse/ up 
              else 
              echo "Migration"
              migrate -database ${DB_URL} -path /databases/clickhouse/ up # Start Migration
              fi
          else
              echo "Empty or not dir"
          fi
}

############################################
#Migrations
case "$1" in
"mysql")
   keyName="MIGR_MYSQL"
   if [[ ! $2 = fix ]]; then
       mysql_migration
   else
       DB=$3
       get_connector
       echo "Force rolback Mysql migration in $3 to $4 version"
       migrate -database ${DB_URL}$DB?x-no-lock=true -path /databases/mysql/$3 force $4
   fi
;;
"mongo")
   keyName="MIGR_MONGO"
   if [[ ! $2 = fix ]]; then
       mongo_migration
   else
   DB=$3
   get_connector
   echo "Force rolback Mongo migration in $3 to $4 version"
   migrate -database ${DB_URL}$3 -path /databases/mongo/$3 force $4
   fi
   ;;
"clickhouse")
   keyName="MIGR_CH"
   if [[ ! $2 = fix ]]; then
       clickhouse_migration
   else
   get_connector
   echo "Force rolback Clickhouse migration in $3 to $4 version"
   migrate -database ${DB_URL} -path /databases/clickhouse/ force $4
   fi
   ;;
esac

