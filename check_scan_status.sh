#!/bin/bash

# Скрипт для проверки статуса сканирования образов в Harbor

HARBOR_URL="http://localhost:8080"
USERNAME="admin"
PASSWORD="Harbor12345"

echo "🔍 Проверка статуса сканирования образов в Harbor..."

# Функция для проверки статуса сканирования образа
check_artifact_scan() {
    local project=$1
    local repo=$2
    local digest=$3
    
    local scan_info=$(curl -s -u "$USERNAME:$PASSWORD" \
        "$HARBOR_URL/api/v2.0/projects/$project/repositories/$repo/artifacts/$digest?with_scan_overview=true" | \
        jq -r '.scan_overview."application/vnd.security.vulnerability.report; version=1.1"')
    
    if [ "$scan_info" != "null" ]; then
        local status=$(echo "$scan_info" | jq -r '.scan_status')
        local start_time=$(echo "$scan_info" | jq -r '.start_time')
        local end_time=$(echo "$scan_info" | jq -r '.end_time')
        
        case $status in
            "Success")
                local summary=$(echo "$scan_info" | jq -r '.summary')
                local total=$(echo "$summary" | jq -r '.total')
                local high=$(echo "$summary" | jq -r '.summary.High // 0')
                local medium=$(echo "$summary" | jq -r '.summary.Medium // 0')
                local low=$(echo "$summary" | jq -r '.summary.Low // 0')
                echo "✅ $project/$repo@${digest:0:19}... - Завершено (Уязвимостей: $total, H:$high M:$medium L:$low)"
                ;;
            "Running")
                echo "🔄 $project/$repo@${digest:0:19}... - Выполняется"
                ;;
            "Error")
                echo "❌ $project/$repo@${digest:0:19}... - Ошибка"
                ;;
            *)
                echo "ℹ️  $project/$repo@${digest:0:19}... - Статус: $status"
                ;;
        esac
    else
        echo "⚠️  $project/$repo@${digest:0:19}... - Нет данных о сканировании"
    fi
}

# Получаем все проекты
projects=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects" | jq -r '.[].name')

total_checked=0
completed=0
running=0
errors=0

for project in $projects; do
    echo ""
    echo "🏗️  Проект: $project"
    
    # Получаем репозитории проекта
    repos=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects/$project/repositories" | jq -r '.[].name')
    
    for repo in $repos; do
        repo_name=$(echo $repo | sed "s/$project\///")
        
        # Получаем артефакты репозитория
        artifacts=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects/$project/repositories/$repo_name/artifacts" | jq -r '.[].digest')
        
        for digest in $artifacts; do
            check_artifact_scan "$project" "$repo_name" "$digest"
            total_checked=$((total_checked + 1))
        done
    done
done

echo ""
echo "📊 Статистика:"
echo "  Всего проверено: $total_checked"
echo "  Завершено: $completed"
echo "  Выполняется: $running"
echo "  Ошибок: $errors"
