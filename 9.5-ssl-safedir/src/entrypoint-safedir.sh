#!/usr/bin/env bash
#
# v1.0.0-mysql    2017-10-15     webmaster@highskillz.com
#
set -e
set -o pipefail
#set -x

SFD_ENTRYPOINT="${SAFEDIR__ENTRYPOINT:-exec ./docker-entrypoint.sh}"

SAFEDIR__DIRPATH="${SAFEDIR__DIRPATH:-/var/lib/postgresql/data}"

# usage mode:
#
#   initialize:     SAFEDIR__TAGHASH=aaaaa67890aaaaa67890    SAFEDIR__DB_INIT=1    SAFEDIR__MODE=single
#   initialize:     SAFEDIR__TAGHASH=aaaaa67890aaaaa67890    SAFEDIR__DB_INIT=1
#   use-safely:     SAFEDIR__TAGHASH=aaaaa67890aaaaa67890
#   use-safely:     SAFEDIR__TAGHASH=aaaaa67890aaaaa67890                          SAFEDIR__MODE=single
#   use-nocheck:    SAFEDIR__DB_INIT=1
#   use-nocheck:    SAFEDIR__ALLOW_EMPTY=1
#   disable-chk:    SAFEDIR__DISABLE_CHECKS=1
#
# SAFEDIR__TAGHASH should be defined as environment variable when executing the container.
# Except for development environments, it should *not* be defined in the Dockerfile or even docker-compose.yml.
#
SAFEDIR__MODE="${SAFEDIR__MODE:-single}"

SFD_ALLOW_EMPTY="${SAFEDIR__DB_INIT:-${SAFEDIR__ALLOW_EMPTY:-0}}"

SFD_CHECK_FN_PREFIX=".safedir-check"
SFD_CHECK_FN_EXT="tag"

function check_dir_is_empty() {
    set -e
    # return 0 if $1 folder does not exist or exists and is empty

    if [ -d "$1" ]; then
        if [ "$(ls -A $1)" ]; then
            return -2
        fi
    fi

    return 0
}

function check_folder_is_safe() {
    set -e
    if [ "$1" == "" ]; then
        echo "SAFEDIR>> Unspecified folder... Aborting;"
        return -1
    fi

    # returns 1 if folder is not safe, 0 otherwise

    [ "${SAFEDIR__DISABLE_CHECKS}" == "1" ] && return 0

    local SFD_TAG_FILEPATH=""

    echo "SAFEDIR>> Starting check of folder [$1]..."
    case "${SAFEDIR__MODE}" in
        "single")
            echo "SAFEDIR>> Detected SAFEDIR__MODE == [${SAFEDIR__MODE}]"
            # we always require the tag to be defined, either for checking, or for creating
            if [ -z "${SAFEDIR__TAGHASH}" ]; then
                echo "SAFEDIR>> ERROR: SAFEDIR__TAGHASH not defined! Aborting!"
                exit -3
            fi

            SFD_TAG_FILEPATH="$1/${SFD_CHECK_FN_PREFIX}.${SFD_CHECK_FN_EXT}"
            ;;
        "multi")
            echo "SAFEDIR>> SAFEDIR__MODE: [${SAFEDIR__MODE}]"
            if [ -z "${SAFEDIR__TAGHASH}" ]; then
                echo "SAFEDIR>> ERROR: SAFEDIR__TAGHASH not defined! Aborting!"
                exit -4
            fi

            SFD_TAG_FILEPATH="${SAFEDIR__DIRPATH}/${SFD_CHECK_FN_PREFIX}.${SAFEDIR__TAGHASH}.${SFD_CHECK_FN_EXT}"
            ;;
        *)
            echo "SAFEDIR>> ERROR: Unknown SAFEDIR__MODE specified!! Aborting!!"
            exit -2
    esac

    echo "SAFEDIR>> Checking existing files and folders..."
    if check_dir_is_empty $1; then
        echo "SAFEDIR>> It looks like this is an empty folder..."

        # We can only accept an empty database folder if we are initializing
        if [ "${SFD_ALLOW_EMPTY}" != "1" ]; then
            echo "SAFEDIR>> ERROR: Found empty folder [${SAFEDIR__DIRPATH}] outside initialization mode. Aborting!"
            exit -21
        fi

        if [ "$2" == "" ]; then
            # since we are initializing, create taghash file (overwriting if exists)
            # to be even stricter, if the file already exists, we could check the taghash (but this would make it even harder to initialize)
            echo "SAFEDIR>> Creating taghash file at [${SFD_TAG_FILEPATH}] with [${SAFEDIR__TAGHASH}] (was empty)"
            echo "${SAFEDIR__TAGHASH}" | tee "${SFD_TAG_FILEPATH}" > /dev/null
        fi
    else
        echo "It looks like the target dir is not empty... [${DIR_EMPTY_check}]"

        if [ "$2" == "" ]; then
            if [ ! -f "${SFD_TAG_FILEPATH}" ]; then
                echo "It looks like the taghash file does not exist..."

                if [ "${SFD_ALLOW_EMPTY}" != "1" ]; then
                    echo "ERROR: Could not find taghash file [${SFD_TAG_FILEPATH}] outside initialization mode. Aborting!"
                    exit -31
                fi

                echo "Creating taghash file at [${SFD_TAG_FILEPATH}] with [${SAFEDIR__TAGHASH}] (was missing)"
                echo "${SAFEDIR__TAGHASH}" | tee "${SFD_TAG_FILEPATH}" > /dev/null
            else
                echo "It looks like the taghash file does indeed exist..."
                if [[ $(< "${SFD_TAG_FILEPATH}") != "${SAFEDIR__TAGHASH}" ]]; then
                    echo "ERROR: Taghash file [${SFD_TAG_FILEPATH}] content did not match [${SAFEDIR__TAGHASH}]. Aborting!"
                    exit -41
                fi
            fi
        fi
    fi
    return 0
}

# ------------------------------------------------------------------
if [ "${SAFEDIR__DISABLE_CHECKS}" != "1" ]; then

    if check_folder_is_safe "${SAFEDIR__DIRPATH}"               ; then echo OK; else echo "Not safe [1]"; exit -51; fi
    # if check_folder_is_safe "${SAFEDIR__DIRPATH}/mysql" "NOTAG" ; then echo OK; else exit "Not safe [2]"; exit -52; fi
    # if check_folder_is_safe "${SAFEDIR__DIRPATH}/sys"   "NOTAG" ; then echo OK; else exit "Not safe [3]"; exit -53; fi

fi

# calling the parent image entrypoint script
# using exec as per https://docs.docker.com/engine/userguide/eng-image/dockerfile_best-practices/#entrypoint
${SFD_ENTRYPOINT} "$@"
