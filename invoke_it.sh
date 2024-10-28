#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

function sha256Hash() {
    printf "$1" | ${OPENSSL_BIN} dgst -sha256 -binary -hex | sed 's/^.* //'
}

function log() {
    local message="$1"
    local details="$2"

    printf "${message}\n" >&2
    printf "${details}\n\n" | sed 's/^/    /' >&2
}

function to_hex() {
    printf "$1" | od -A n -t x1 | tr -d [:space:]
}

function hmac_sha256() {
    printf "$2" | \
        ${OPENSSL_BIN} dgst -binary -hex -sha256 -mac HMAC -macopt hexkey:"$1" | \
        sed 's/^.* //'
}

## http://docs.aws.amazon.com/general/latest/gr/sigv4-create-canonical-request.html
function task_1() {
    local http_request_method="$1"
    local payload="$2"
    local canonical_uri="/${api_uri}"
    local canonical_query=""

    local header_host="host:${api_host}"
    local canonical_headers="${header_host}\n${header_x_amz_date}"

    local request_payload=$(sha256Hash "${payload}")
    local canonical_request="${http_request_method}\n${canonical_uri}\n${canonical_query}\n${canonical_headers}\n\n${signed_headers}\n${request_payload}"

    log "canonical_request=" "${canonical_request}"
    printf "$(sha256Hash ${canonical_request})"
}

## http://docs.aws.amazon.com/general/latest/gr/sigv4-create-string-to-sign.html
function task_2() {
    local hashed_canonical_request="$1"
    local sts="${algorithm}\n${timestamp}\n${credential_scope}\n${hashed_canonical_request}"
    log "string_to_sign=" "${sts}"
    printf "${sts}"
}

## http://docs.aws.amazon.com/general/latest/gr/sigv4-calculate-signature.html
function task_3() {
    local secret=$(to_hex "AWS4${aws_secret_key}")
    local k_date=$(hmac_sha256 "${secret}" "${today}")
    local k_region=$(hmac_sha256 "${k_date}" "${aws_region}")
    local k_service=$(hmac_sha256 "${k_region}" "${aws_service}")
    local k_signing=$(hmac_sha256 "${k_service}" "aws4_request")
    local string_to_sign="$1"

    local signature=$(hmac_sha256 "${k_signing}" "${string_to_sign}" | sed 's/^.* //')
    log "signature=" "${signature}"
    printf "${signature}"
}

## http://docs.aws.amazon.com/general/latest/gr/sigv4-add-signature-to-request.html#sigv4-add-signature-auth-header
function task_4() {
    local credential="Credential=${aws_access_key}/${credential_scope}"
    local s_headers="SignedHeaders=${signed_headers}"
    local signature="Signature=$1"

    local authorization_header="Authorization: ${algorithm} ${credential}, ${s_headers}, ${signature}"
    log "authorization_header=" "${authorization_header}"
    printf "${authorization_header}"
}

function sign_it() {
    local method="$1"
    local payload="$2"
    local hashed_canonical_request=$(task_1 "${method}" "${payload}")
    local string_to_sign=$(task_2 "${hashed_canonical_request}")
    local signature=$(task_3 "${string_to_sign}")
    local authorization_header=$(task_4 "${signature}")
    printf "${authorization_header}"
}

function invoke_it() {
    local http_method="$1"
    local request_body="$2"
    local request_payload=""
    local profile="${3:-default}"
    if [[ ! -z "${request_body}" ]]; then
        request_payload=$(cat "${request_body}")
    fi
    local aws_session_token=$(echo "$credentials" | cut -d':' -f3)

    local authorization_header=$(sign_it "${http_method}" "${request_payload}" "$aws_access_key" "$aws_secret_key" "$aws_session_token")
    local credentials=$(parse_aws_credentials "$profile")
    local aws_access_key=$(echo "$credentials" | cut -d':' -f1)
    local aws_secret_key=$(echo "$credentials" | cut -d':' -f2)
    local session_token_header="x-amz-security-token:${aws_session_token}"
    printf "> ${http_method}-ing ${api_url}\n"
    if [[ -z "${request_body}" ]]; then
        # response=$(curl -si -v -X $http_method '$api_url' -H '$authorization_header' -H '$header_x_amz_date' -H '$session_token_header')
        local curl_command="curl -si -X $http_method '$api_url' -H '$authorization_header' -H '$header_x_amz_date' -H '$session_token_header'"
        # echo "$response"
        echo "printing raw curl call now"
        echo "$curl_command"
    else
        printf "(including body: ${request_body})\n"
        local curl_command="curl -si -X $http_method '$api_url' -H '$authorization_header' -H '$header_x_amz_date' -H '$session_token_header' --data '$request_payload'"
        echo "$curl_command"
    fi
}


function install_openssl() {
    # macOS provides an outdated OpenSSL so you need to use a later one installed from Homebrew

    # assume openssl is in PATH on Linux systems
    OPENSSL_BIN="openssl"

    # only run on macOS
    uname | grep -q ^Darwin
    if [ $? -eq 0 ]; then
        which brew > /dev/null
        if [ $? -ne 0 ]; then
            echo "Homebrew is a prerequisite to install the latest OpenSSL on macOS (hint: install brew via 'https://brew.sh/')" >&2
            exit 1
        fi

        OPENSSL_BIN="$(brew list openssl | awk '/\/bin\/openssl/')"
        if [[ -z "${OPENSSL_BIN}" ]]; then
            echo "Homebrew OpenSSL not installed (hint: 'brew install openssl')" >&2
            exit 1
        fi
    fi
}

function parse_aws_credentials() {
    local profile="$1"
    local ini_file="$HOME/.aws/credentials"
    local aws_access_key=""
    local aws_secret_key=""
    local aws_session_token=""
    local in_section=false

    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '[:space:]')  # Remove all spaces
        if [[ "$line" =~ ^\[(.*)\]$ ]]; then  # Match profile section
            if [[ "${BASH_REMATCH[1]}" == "$profile" ]]; then
                in_section=true
            else
                in_section=false
            fi
        elif $in_section && [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            case "$key" in
                aws_access_key_id) aws_access_key="$value" ;;
                aws_secret_access_key) aws_secret_key="$value" ;;
                aws_session_token) aws_session_token="$value" ;;
            esac
        fi
    done < "$ini_file"

    if [[ -z "$aws_access_key" || -z "$aws_secret_key" ]]; then
        echo "ERROR: Credentials not found for profile '$profile'" >&2
        exit 1
    fi
    echo "$aws_access_key:$aws_secret_key:$aws_session_token"  # Return credentials in a single line
}



function main() {
    ## parse arguments
    until [ $# -eq 0 ]; do
        name=${1:1}; shift;
        if [[ -z "$1" || $1 == -* ]] ; then eval "export $name=''"; else eval "export $name=$1"; shift; fi
    done

    if [ -z "${credentials-}" ] ; then
        credentials=$(parse_aws_credentials "${awsprofile:=default}")
    fi

    if [ -z "${credentials-}" ] || [ -z "${url-}" ] || [ -z "${method-}" ] ; then
        log "sample usage:" "<script> -method <http_method> [-awsprofile <profile>] [-credentials <aws_access_key>:<aws_secret_key>] -url <c_url> -body <body>"
        exit 1
    fi

    if [[ ! -z "${body-}" && ! -f "${body}" ]] ; then
        echo "ERR body file '${body}' - not found"
        exit 1
    fi

    install_openssl

    local method="${method}"
    local aws_access_key=$(cut -d':' -f1 <<<"${credentials}")
    local aws_secret_key=$(cut -d':' -f2 <<<"${credentials}")

    local api_url="${url}"
    log "aws_access_key=" "${aws_access_key}"
    log "aws_secret_key=" "${aws_secret_key}"
    log "api_url=" "${api_url}"

    local timestamp=${timestamp-$(date -u +"%Y%m%dT%H%M%SZ")} #$(date -u +"%Y%m%dT%H%M%SZ") #"20171226T112335Z"
    local today=${today-$(date -u +"%Y%m%d")}  # $(date -u +"%Y%m%d") #20171226
    log "timestamp=" "${timestamp}"
    log "today=" "${today}"

    local api_host=$(printf ${api_url} | awk -F/ '{print $3}')
    local api_uri=$(printf ${api_url} | grep / | cut -d/ -f4-)

    local aws_region=$(cut -d'.' -f3 <<<"${api_host}")
    local aws_service=$(cut -d'.' -f2 <<<"${api_host}")

    local algorithm="AWS4-HMAC-SHA256"
    local credential_scope="${today}/${aws_region}/${aws_service}/aws4_request"

    local signed_headers="host;x-amz-date"
    local header_x_amz_date="x-amz-date:${timestamp}"

    invoke_it "${method}" "${body-}"

    echo -e "\n\nDONE!!!"
}

main "$@"

