#!/bin/bash

# Скрипт для запуска сканирования всех образов в Harbor
# Использует curl для обхода проблем с CSRF токенами

HARBOR_URL="http://localhost:8080"
USERNAME="admin"
PASSWORD="Harbor12345"

echo "🔍 Запуск сканирования всех образов в Harbor..."

# Функция для запуска сканирования образа
scan_artifact() {
    local project=$1
    local repo=$2
    local digest=$3
    
    echo "📦 Сканирование: $project/$repo@${digest:0:19}..."
    
    response=$(curl -s -X POST -u "$USERNAME:$PASSWORD" \
        -H "Content-Type: application/json" \
        -H "X-Requested-With: XMLHttpRequest" \
        -d '{}' \
        "$HARBOR_URL/api/v2.0/projects/$project/repositories/$repo/artifacts/$digest/scan")
    
    if [ $? -eq 0 ]; then
        echo "✅ Сканирование запущено для $project/$repo@${digest:0:19}..."
    else
        echo "❌ Ошибка сканирования для $project/$repo@${digest:0:19}..."
    fi
}

# Получаем все проекты
echo "📋 Получение списка проектов..."
projects=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects" | jq -r '.[].name')

total_scanned=0

for project in $projects; do
    echo ""
    echo "🏗️  Проект: $project"
    
    # Получаем репозитории проекта
    repos=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects/$project/repositories" | jq -r '.[].name')
    
    for repo in $repos; do
        repo_name=$(echo $repo | sed "s/$project\///")
        echo "  📦 Репозиторий: $repo_name"
        
        # Получаем артефакты репозитория
        artifacts=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects/$project/repositories/$repo_name/artifacts" | jq -r '.[].digest')
        
        for digest in $artifacts; do
            scan_artifact "$project" "$repo_name" "$digest"
            total_scanned=$((total_scanned + 1))
            sleep 1  # Небольшая пауза между запросами
        done
    done
done

echo ""
echo "📊 Итого отправлено запросов на сканирование: $total_scanned"
echo "✅ Готово!"
