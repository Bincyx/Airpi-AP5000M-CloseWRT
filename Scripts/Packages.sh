#!/bin/bash
set -euo pipefail

# 彩色日志函数
log_info()  { echo -e "\033[32m[INFO]\033[0m $*"; }
log_warn()  { echo -e "\033[33m[WARN]\033[0m $*"; }
log_error() { echo -e "\033[31m[ERROR]\033[0m $*"; }

# 安装和更新软件包
UPDATE_PACKAGE() {
    local PKG_NAME=$1
    local PKG_REPO=$2
    local PKG_BRANCH=$3
    local PKG_SPECIAL=${4:-""}
    shift 4
    local PKG_LIST=("$PKG_NAME" "$@")
    local REPO_NAME=${PKG_REPO#*/}

    log_info "Updating package: $PKG_NAME from $PKG_REPO ($PKG_BRANCH)"

    # 删除旧包目录
    for NAME in "${PKG_LIST[@]}"; do
        local FOUND_DIRS
        FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null || true)
        if [ -n "$FOUND_DIRS" ]; then
            while read -r DIR; do
                rm -rf "$DIR"
                log_warn "Deleted old directory: $DIR"
            done <<< "$FOUND_DIRS"
        else
            log_info "No existing directory found for: $NAME"
        fi
    done

    # 克隆仓库
    git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git" || {
        log_error "Clone failed: $PKG_REPO"
        exit 1
    }

    # 特殊处理
    if [[ "$PKG_SPECIAL" == "pkg" ]]; then
        find "./$REPO_NAME"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
        rm -rf "./$REPO_NAME/"
    elif [[ "$PKG_SPECIAL" == "name" ]]; then
        mv -f "$REPO_NAME" "$PKG_NAME"
    fi

    log_info "Package $PKG_NAME updated successfully!"
}

# 更新软件包版本
UPDATE_VERSION() {
    local PKG_NAME=$1
    local PKG_MARK=${2:-false}
    local PKG_FILES
    PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile" || true)

    if [ -z "$PKG_FILES" ]; then
        log_error "$PKG_NAME not found!"
        return
    fi

    log_info "$PKG_NAME version update started!"

    for PKG_FILE in $PKG_FILES; do
        local PKG_REPO
        PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+" "$PKG_FILE" || true)
        if [ -z "$PKG_REPO" ]; then
            log_warn "No GitHub repo found in $PKG_FILE"
            continue
        fi

        local PKG_TAG
        PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name // empty")

        if [ -z "$PKG_TAG" ]; then
            log_warn "No release tag found for $PKG_REPO"
            continue
        fi

        local OLD_VER NEW_VER NEW_HASH
        OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE" || true)
        NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')

        if dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
            local PKG_URL
            PKG_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE" | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
            NEW_HASH=$(curl -sL "$PKG_URL" | sha256sum | cut -d ' ' -f 1)

            sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
            sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"

            log_info "$PKG_FILE updated to version $NEW_VER"
        else
            log_info "$PKG_FILE already at latest version ($OLD_VER)"
        fi
    done
}

# 并行更新示例
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-24.10" &
UPDATE_PACKAGE "homeproxy" "immortalwrt/homeproxy" "master" &
wait
