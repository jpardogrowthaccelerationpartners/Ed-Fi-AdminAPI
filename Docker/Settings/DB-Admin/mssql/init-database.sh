#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.
#

set -e
set +x
MSSQL_USER=$SQLSERVER_USER
MSSQL_PASSWORD=$SQLSERVER_PASSWORD
MSSQL_SA_PASSWORD=$SA_PASSWORD
MSSQL_ADMIN_DB=$SQLSERVER_ADMIN_DATASOURCE
MSSQL_SECURITY_DB=$SQLSERVER_SECURITY_DATASOURCE


function does_edfi_admin_db_exist() {
    local result=$(/opt/mssql-tools18/bin/sqlcmd -S "(local)" -U "sa" -P $MSSQL_SA_PASSWORD -C -Q "IF EXISTS (SELECT name FROM sys.databases WHERE name = 'EdFi_Admin') PRINT 'Database exists' ELSE PRINT 'Database does not exist'" -h -1)

    if [[ "$result" == *"Database exists"* ]]; then
        echo "Database exists"
        return 0
    else
        echo "Database does not exist"
        return 1
    fi
}
if ! does_edfi_admin_db_exist; then
    echo "Creating base Admin and Security databases..."
    /opt/sqlpackage/sqlpackage /Action:Import /tsn:"(local),1433" /tdn:"EdFi_Security" /tu:"sa" /tp:"$MSSQL_SA_PASSWORD" /sf:"/tmp/EdFi_Security.bacpac" /ttsc:true
    /opt/sqlpackage/sqlpackage /Action:Import /tsn:"(local),1433" /tdn:"EdFi_Admin" /tu:"sa" /tp:"$MSSQL_SA_PASSWORD" /sf:"/tmp/EdFi_Admin.bacpac" /ttsc:true

    # Force sorting by name following C language sort ordering, so that the sql scripts are run
    # sequentially in the correct alphanumeric order
    echo "Running Admin Api database migration scripts..."

    for FILE in `LANG=C ls /tmp/AdminApiScripts/MsSql/*.sql | sort -V`
    do
        echo "Running script: ${FILE}..."
        /opt/mssql-tools18/bin/sqlcmd -S "(local),1433" -U "sa" -P "$MSSQL_SA_PASSWORD" -d "EdFi_Admin" -i $FILE -C
    done

    /opt/mssql-tools18/bin/sqlcmd -S "(local),1433" -C -U sa -P $MSSQL_SA_PASSWORD -Q "IF NOT EXISTS (SELECT * FROM master.sys.server_principals WHERE name = 'edfi') BEGIN CREATE LOGIN [edfi] WITH PASSWORD = '$SQLSERVER_PASSWORD'; END; ALTER AUTHORIZATION ON DATABASE::EdFi_Security TO [edfi]; ALTER AUTHORIZATION ON DATABASE::EdFi_Admin TO [edfi];"

    echo "Finish Admin Api database migration scripts..."
fi
