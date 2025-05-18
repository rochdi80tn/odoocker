#!/bin/bash

set -e

# Array to store all repository names
processed_modules=()

# Function to construct the clone command
construct_clone_command() {
    local repo_type=$1
    local repo_url=$2
    case $repo_type in
        private) echo "git clone https://${GITHUB_USER}:${GITHUB_ACCESS_TOKEN}@${repo_url#https://}" ;;
        enterprise) echo "git clone https://${ENTERPRISE_USER}:${ENTERPRISE_ACCESS_TOKEN}@${repo_url#https://} ${ENTERPRISE_ADDONS}" ;;
        public) echo "git clone $repo_url" ;;
    esac
}

# Function to clone and copy modules based on conditions
clone_and_copy_modules() {
    local repo_type=$1
    local repo_url=$2
    local clone_cmd=$(construct_clone_command $repo_type $repo_url)
    local repo_name=$(basename -s .git "$repo_url")

    shift 2
    local modules_conditions=("$@")
    local should_clone=false
    # Clone and copy logic for enterprise repository
    if [[ $repo_type == "enterprise" ]]; then
        [[ ${modules_conditions[0]} == true ]] && should_clone=true
        if [ -n "$ENTERPRISE_USER" ] && [ -n "$ENTERPRISE_ACCESS_TOKEN" ] && [[ $should_clone == true ]]; then
            echo "Cloning enterprise repository: $clone_cmd"
            $clone_cmd --depth 1 --branch ${ODOO_TAG} --single-branch --no-tags
        fi
    else
        # Determine if any module has a true condition
        if [[ ${#modules_conditions[@]} -eq 1 ]]; then
            [[ ${modules_conditions[0]} == true ]] && should_clone=true
        else
            for (( i=1; i<${#modules_conditions[@]}; i+=2 )); do
                if [[ ${modules_conditions[i]} == true ]]; then
                    should_clone=true
                    break
                fi
            done
        fi

        # Clone the repo if should_clone is true and it's not already cloned
        if [[ $should_clone == true ]]; then
            echo ""
            if [[ ! -d "/download/$repo_name" ]]; then
                echo "Cloning repository: $clone_cmd --depth 1 --branch ${ODOO_TAG} --single-branch --no-tags /download/$repo_name"
                $clone_cmd --depth 1 --branch ${ODOO_TAG} --single-branch --no-tags /download/$repo_name
            else
                # # If the repo is already cloned, pull the latest changes
                if git -C "/download/$repo_name" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
                    echo -n "Checking if repository /download/$repo_name..."

                    # Fetch the latest changes from the remote
                    cd /download/$repo_name
                    git fetch --quiet origin ${ODOO_TAG}

                    # Compare the local HEAD with the remote branch
                    LOCAL_COMMIT=$(git rev-parse HEAD)
                    REMOTE_COMMIT=$(git rev-parse origin/${ODOO_TAG})

                    if [[ "$LOCAL_COMMIT" == "$REMOTE_COMMIT" ]]; then
                        echo " already up-to-date"
                    else
                        echo " requires updating... "
                        git reset --hard origin/${ODOO_TAG}
                    fi
                else
                    echo "/download/$repo_name is not a valid git repository. Re-cloning..."
                    rm -rf "/download/$repo_name"
                    $clone_cmd --depth 1 --branch ${ODOO_TAG} --single-branch --no-tags /download/$repo_name
                fi
            fi
        fi

        # Copy the modules if the condition is true
        if [[ $should_clone == true ]]; then
            for (( i=0; i<${#modules_conditions[@]}; i+=2 )); do
                local module=${modules_conditions[i]}
                local condition=${modules_conditions[i+1]}
                if [[ $condition == true ]]; then
                    echo "  > Copying ${module} from /download/${repo_name} into ${THIRD_PARTY_ADDONS}"
                    rm -rf ${THIRD_PARTY_ADDONS}/${module} && cp -r /download/${repo_name}/${module} ${THIRD_PARTY_ADDONS}/${module}
                    # Add the repo_name to the array
                    processed_modules+=("$module")
                fi
            done
        fi
    fi
}

# Function to manually expand environment variables in a string
expand_env_vars() {
    while IFS=' ' read -r -a words; do
        for word in "${words[@]}"; do
            if [[ $word == \$\{* ]]; then
                # Remove the leading '${' and the trailing '}' from the word
                varname=${word:2:-1}
                # Check if the variable is set and not empty
                if [ -n "${!varname+x}" ]; then
                    echo -n "${!varname} " # Substitute with its value
                else
                    echo -n "false " # Default to false if not set
                fi
            else
                echo -n "$word "
            fi
        done
        echo
    done <<< "$1"
}

# Read the configuration file and process each line
# mkdir -p ${ENTERPRISE_ADDONS}
# mkdir -p ${THIRD_PARTY_ADDONS}
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    clone_and_copy_modules $(expand_env_vars "$line")
done < "third-party-addons.txt"


# Display all collected repository names at the end
echo "${processed_modules[@]}" > /download/processed_modules.txt
echo
echo "Repositories processed list saved in /download/processed_modules.txt"
# for module in "${processed_modules[@]}"; do
#     echo "  - $module"
# done