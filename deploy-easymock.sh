#!/bin/bash

# This script expects:
# - jira_user / jira_password to be available environment variables
# - gpg_passphrase to be an environment variable
# - the version to be deployed as the first parameter
# - sf_user to be an environment variable with its associated ssh key
# - sf_api_key to be an environment variable

# to exit in case of error
set -e

# make sure the version is passed in parameter
if [ "$1" == "" ]; then
    echo "Version to deploy should be provided"
    exit 1
fi

# make sure all variables are set
if [ -z "$jira_user" ] || [ -z "$jira_password" ] || [ -z "$gpg_passphrase" ] || [ -z "$sf_user" ] || [ -z "$sf_api_key" ]; then
    echo "Variables jira_user, jira_password, gpg_assphrase, sf_user and sf_api_key should be provided"
    exit 1
fi

# make sure the script is launched from the project root directory
if [ "$PWD" != "$(dirname $0)" ]
    echo "The script should be launched from EasyMock root directory"
    exit 1
end

version=$1

echo "Make sure we have a target directory"
test ! -d target && mkdir target

echo

echo "Retrieve Jira version id for version $version"
escaped_version=$(echo $version | sed "s/\([0-9]*\)\.\([0-9]*\)/\1\\\.\2/")
jira_version_id=$(curl --silent "http://jira.codehaus.org/rest/api/2/project/EASYMOCK/versions" | grep -o "\"id\":\"[0-9]*\",\"description\":\"EasyMock $escaped_version\"" | cut -d'"' -f4)
echo "Jira version id = ${jira_version_id}"

echo

echo "Check that the jira_version was correctly found"
result=$(curl -s -o /dev/null -I -w "%{http_code}" "http://jira.codehaus.org/rest/api/2/version/${jira_version_id}")
[ $result -eq 200 ]

echo

echo "Update Release Notes"
release_notes_page="http://jira.codehaus.org/secure/ReleaseNote.jspa?version=${jira_version_id}&styleName=Text&projectId=12103"
release_notes=$(curl --silent "$release_notes_page")
echo "$release_notes" | sed -n "/<textarea rows=\"40\" cols=\"120\">/,/<\/textarea>/p" | grep -v "textarea" > "target/ReleaseNotes.txt"
echo "For details, please see $release_notes_page" >> "target/ReleaseNotes.txt"
release_notes=$(cat "target/ReleaseNotes.txt")
echo "$release_notes"

echo

echo "Build and deploy"
mvn -T 8.0C clean deploy -PfullBuild,deployBuild -Dgpg.passphrase=${gpg_passphrase}

echo

echo "Release the version in Jira"
curl -D- -u $jira_user:$jira_password -X PUT --data '{ "released": true }' -H "Content-Type:application/json" https://jira.codehaus.org/rest/api/2/version/${jira_version_id}

echo

echo "Deploy the bundle to SourceForce"
sf_url=${sf_user},easymock@shell.sourceforge.net
sf_version_path=/home/frs/project/easymock/EasyMock/${version}
ssh ${sf_url} create
ssh ${sf_url} "mkdir -p ${sf_version_path}"
scp easymock/target/easymock-${version}-bundle.zip $(sf_url}:$(sf_version_path}/easymock-${version}.zip
scp target/ReleaseNotes.txt $(sf_url}:$(sf_version_path}/readme.txt
curl -H "Accept: application/json" -X PUT -d "default=windows&default=mac&default=linux&default=bsd&default=solaris&default=others" -d "api_key=${sf_api_key}" http://sourceforge.net/projects/easymock/files/EasyMock/${version}/easymock-${version}.zip
result=$(curl -s -o /dev/null -I -w "%{http_code}" "http://sourceforge.net/projects/easymock/files/EasyMock/$version/")
[ $result -eq 200 ]

echo

echo "Close the deployment at Sonatype Nexus UI"

 (https://oss.sonatype.org/index.html#stagingRepositories)
  More details on the deployment rules here: https://docs.sonatype.org/display/Repository/Sonatype+OSS+Maven+Repository+Usage+Guide
- Release the repository. It will be synced with Maven Central Repository

echo

echo "Update Javadoc"
git rm -rf website/api
cp -r easymock/target/apidocs website/api
git add website/api
git commit -m "Upgrade javadoc to version $version"

echo

echo "Update the version on the website"
sed -i '' "s/latest_version: .*/latest_version: $version/" 'website/_config.yml'

echo "Update website"
sh deploy-website.sh

echo

echo "Send new release mail"
mail="$(cat mail.txt)"
mail="${mail//@version@/$version}"
mail="${mail/@release_notes@/$release_notes}"
echo "$mail" > target/mail.txt
sendmail easymock@yahoogroups.com < target/mail.txt