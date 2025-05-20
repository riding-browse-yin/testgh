#!/bin/bash

# 设置错误处理：任何命令失败时，打印错误信息并继续下一个循环迭代
# set -e # Don't exit immediately on error, let the loop continue

ASSETS_DIR="./assets"
REMOTE_NAME="origin" # 远程仓库名称
# CURRENT_BRANCH=$(git branch --show-current 2>/dev/null) # 获取当前分支名

# 检查是否在 Git 仓库中
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Error: Not inside a Git work tree. Please run this script in a Git repository."
    exit 1
fi

# 检查远程仓库是否存在
if ! git remote get-url "${REMOTE_NAME}" > /dev/null 2>&1; then
    echo "Error: Remote '${REMOTE_NAME}' not found. Please add a remote named '${REMOTE_NAME}'."
    exit 1
fi

# 循环无限次
while true; do
    echo "--- $(date) - Starting new iteration ---"

    # 1. 确保 assets 目录存在并清空
    mkdir -p "${ASSETS_DIR}" || { echo "Error: Could not create directory ${ASSETS_DIR}. Skipping iteration."; continue; }

    # 2. 创建随机数量的随机大小文件
    FILE_COUNT=$(shuf -i 1-11 -n 1)
    echo "Creating ${FILE_COUNT} random files..."

    FILES_CREATED=0
    for i in $(seq 1 ${FILE_COUNT}); do
        FILE_SIZE_KB=$(shuf -i 24-48 -n 1)
        FILE_SIZE_BYTES=$(( ${FILE_SIZE_KB} * 1024 ))
        # 使用当前纳秒时间戳+随机数作为文件名，确保唯一性
        FILENAME="${ASSETS_DIR}/file_$(date +%s%N)_${RANDOM}.txt"

        # 使用 /dev/urandom 生成随机数据
        head -c "${FILE_SIZE_BYTES}" /dev/urandom > "${FILENAME}"
        if [ $? -eq 0 ]; then
            echo "  Created ${FILENAME} (${FILE_SIZE_KB} KB)"
            FILES_CREATED=$((FILES_CREATED+1))
        else
            echo "  Warning: Could not create file ${FILENAME}. Skipping it."
        fi
    done

    if [ "${FILES_CREATED}" -eq 0 ]; then
        echo "No files were successfully created. Skipping commit and push."
        continue # 跳过当前迭代的剩余部分
    fi

    # 3. Git 添加、提交、推送
    echo "Adding files to git..."
    git add "${ASSETS_DIR}/"
    if [ $? -ne 0 ]; then
        echo "Error: git add failed. Skipping commit and push."
        continue
    fi

    # 生成提交信息 (当前毫秒级时间戳的 SHA256)
    TIMESTAMP_MS=$(date +%s%3N) # %3N for milliseconds, check your date command support
    if [ -z "$TIMESTAMP_MS" ]; then
       echo "Warning: Could not get millisecond timestamp. Using second timestamp."
       TIMESTAMP_MS=$(date +%s)
    fi
    COMMIT_MSG=$(echo -n "${TIMESTAMP_MS}" | sha256sum | awk '{print $1}')
    echo "Committing with message: ${COMMIT_MSG}"

    git commit -m "${COMMIT_MSG}"
    if [ $? -ne 0 ]; then
        echo "Warning: git commit failed (possibly nothing changed or other error). Skipping push."
        # Check if the failure was due to nothing to commit
        if git status --porcelain | grep -q "^"; then
             echo "  ... git status indicates changes, but commit failed. Investigate manually."
             # We still skip push if commit failed
        else
             echo "  ... git status indicates nothing to commit. This shouldn't happen if files were created."
        fi
        continue # Skip push and tag steps
    fi

    # 获取当前分支名
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
    if [ -z "$CURRENT_BRANCH" ]; then
         echo "Error: Not on a branch. Cannot push commits or tags. Breaking loop."
         break # 无法推送，脚本无法继续有意义的工作，退出
    fi

    echo "Pushing commit to ${REMOTE_NAME}/${CURRENT_BRANCH}..."
    git push "${REMOTE_NAME}" "${CURRENT_BRANCH}"
    if [ $? -ne 0 ]; then
        echo "Error: git push failed. Check network, permissions, conflicts, etc. Continuing loop."
        continue # 推送失败，但可能只是临时问题，继续下一次尝试
    fi

    # 4. 生成和推送标签
    TAG_COUNT=$(shuf -i 1-7 -n 1)
    echo "Creating ${TAG_COUNT} random tags..."

    TAGS_CREATED=0
    for i in $(seq 1 ${TAG_COUNT}); do
        # 生成用于标签名基准的随机24位数字字符串
        RANDOM_24_DIGITS=$(head /dev/urandom | tr -dc '0-9' | head -c 24)
        if [ -z "$RANDOM_24_DIGITS" ]; then
            echo "Warning: Could not generate random digits for tag name. Skipping tag creation."
            continue
        fi
        # 生成标签名 (随机24位数字的 SHA512)
        TAG_NAME=$(echo -n "${RANDOM_24_DIGITS}" | sha512sum | awk '{print $1}')

        # 创建本地标签
        echo "  Creating tag: ${TAG_NAME}"
        git tag "${TAG_NAME}"
        if [ $? -eq 0 ]; then
            TAGS_CREATED=$((TAGS_CREATED+1))
        else
            echo "  Warning: Could not create local tag ${TAG_NAME} (maybe already exists?). Skipping."
            # Git will fail if tag name already exists locally
        fi
    done

    if [ "${TAGS_CREATED}" -gt 0 ]; then
        echo "Pushing tags..."
        # 推送所有本地新标签
        git push "${REMOTE_NAME}" --tags
        if [ $? -ne 0 ]; then
            echo "Error: git push --tags failed. Check network, permissions, conflicts, etc. Continuing loop."
        else
            echo "Tags pushed successfully."
        fi
    else
        echo "No new tags were successfully created locally this iteration to push."
    fi

    echo "--- Iteration finished ---"
    # 循环将立即开始下一轮，没有延迟
    # echo "Waiting before next iteration..."
    # sleep 1 # Uncomment if you want a small delay between iterations
done