#!/bin/bash

# Скрипт для проверки неотсканированных образов в проекте Harbor

HARBOR_URL="http://localhost:8080"
USERNAME="admin"
PASSWORD="Harbor12345"

# Проверяем аргументы
if [ $# -eq 0 ]; then
    echo "Использование: $0 <project_name> [--all]"
    echo ""
    echo "Примеры:"
    echo "  $0 library"
    echo "  $0 test_project"
    echo "  $0 library --all"
    echo ""
    echo "Доступные проекты:"
    curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects" | jq -r '.[].name'
    exit 1
fi

PROJECT_NAME=$1
SHOW_ALL=false

# Проверяем флаг --all
if [ "$2" = "--all" ]; then
    SHOW_ALL=true
fi

echo "🔍 Проверка статуса сканирования образов в проекте: $PROJECT_NAME"

# Проверяем, существует ли проект
project_exists=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects" | jq -r --arg project "$PROJECT_NAME" '.[] | select(.name == $project) | .name')

if [ -z "$project_exists" ]; then
    echo "❌ Проект '$PROJECT_NAME' не найден!"
    echo ""
    echo "Доступные проекты:"
    curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects" | jq -r '.[].name'
    exit 1
fi

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
                local critical=$(echo "$summary" | jq -r '.summary.Critical // 0')
                local unknown=$(echo "$summary" | jq -r '.summary.Unknown // 0')
                local fixable=$(echo "$summary" | jq -r '.fixable // 0')
                
                # Получаем информацию о сканере
                local scanner_name=$(echo "$scan_info" | jq -r '.scanner.name // "Unknown"')
                local scanner_vendor=$(echo "$scan_info" | jq -r '.scanner.vendor // "Unknown"')
                local scanner_version=$(echo "$scan_info" | jq -r '.scanner.version // "Unknown"')
                
                # Определяем уровень критичности
                local severity_level=""
                if [ "$critical" -gt 0 ]; then
                    severity_level="🔴 КРИТИЧЕСКИЙ"
                elif [ "$high" -gt 0 ]; then
                    severity_level="🟠 ВЫСОКИЙ"
                elif [ "$medium" -gt 0 ]; then
                    severity_level="🟡 СРЕДНИЙ"
                elif [ "$low" -gt 0 ]; then
                    severity_level="🟢 НИЗКИЙ"
                else
                    severity_level="✅ БЕЗОПАСНЫЙ"
                fi
                
                if [ "$SHOW_ALL" = true ]; then
                    echo "✅ $project/$repo@${digest:0:19}... - $severity_level"
                    echo "    📊 Уязвимости: $total (C:$critical H:$high M:$medium L:$low U:$unknown)"
                    echo "    🔧 Исправимо: $fixable"
                fi
                
                # Добавляем к общей статистике
                total_vulnerabilities=$((total_vulnerabilities + total))
                total_critical=$((total_critical + critical))
                total_high=$((total_high + high))
                total_medium=$((total_medium + medium))
                total_low=$((total_low + low))
                total_unknown=$((total_unknown + unknown))
                total_fixable=$((total_fixable + fixable))
                
                # Сохраняем информацию о сканере проекта (только один раз)
                if [ -z "$project_scanner_name" ]; then
                    project_scanner_name="$scanner_name"
                    project_scanner_vendor="$scanner_vendor"
                    project_scanner_version="$scanner_version"
                fi
                
                # Добавляем сканер в список
                local scanner_info="$scanner_name $scanner_version ($scanner_vendor)"
                if [ -z "$scanner_list" ]; then
                    scanner_list="$scanner_info"
                else
                    scanner_list="$scanner_list|$scanner_info"
                fi
                
                return 0  # Отсканирован
                ;;
            "Running")
                echo "🔄 $project/$repo@${digest:0:19}... - Выполняется сканирование"
                return 1  # Не отсканирован
                ;;
            "Error")
                echo "❌ $project/$repo@${digest:0:19}... - Ошибка сканирования"
                return 1  # Не отсканирован
                ;;
            "Pending")
                echo "⏳ $project/$repo@${digest:0:19}... - Ожидает сканирования"
                return 1  # Не отсканирован
                ;;
            *)
                echo "❓ $project/$repo@${digest:0:19}... - Неизвестный статус: $status"
                return 1  # Не отсканирован
                ;;
        esac
    else
        echo "⚠️  $project/$repo@${digest:0:19}... - Нет данных о сканировании"
        return 1  # Не отсканирован
    fi
}

echo "🏗️  Проект: $PROJECT_NAME"

# Получаем информацию о сканере проекта (из первого отсканированного образа)
project_scanner_name=""
project_scanner_vendor=""
project_scanner_version=""

# Получаем репозитории проекта
repos=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects/$PROJECT_NAME/repositories" | jq -r '.[].name')

if [ -z "$repos" ]; then
    echo "❌ В проекте '$PROJECT_NAME' нет репозиториев!"
    exit 1
fi

total_artifacts=0
scanned_count=0
unscanned_count=0
running_count=0
error_count=0
pending_count=0

# Статистика уязвимостей
total_vulnerabilities=0
total_critical=0
total_high=0
total_medium=0
total_low=0
total_unknown=0
total_fixable=0

# Статистика сканеров (используем простые переменные)
scanner_list=""

echo ""
if [ "$SHOW_ALL" = true ]; then
    echo "📋 Статус всех образов:"
else
    echo "⚠️  Неотсканированные образы:"
fi
echo ""

for repo in $repos; do
    repo_name=$(echo $repo | sed "s/$PROJECT_NAME\///")
    
    # Получаем артефакты репозитория
    artifacts=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects/$PROJECT_NAME/repositories/$repo_name/artifacts" | jq -r '.[].digest')
    
    if [ -z "$artifacts" ]; then
        continue
    fi
    
    for digest in $artifacts; do
        total_artifacts=$((total_artifacts + 1))
        
        if check_artifact_scan "$PROJECT_NAME" "$repo_name" "$digest"; then
            scanned_count=$((scanned_count + 1))
        else
            unscanned_count=$((unscanned_count + 1))
            
            # Дополнительная статистика для неотсканированных
            scan_info=$(curl -s -u "$USERNAME:$PASSWORD" \
                "$HARBOR_URL/api/v2.0/projects/$PROJECT_NAME/repositories/$repo_name/artifacts/$digest?with_scan_overview=true" | \
                jq -r '.scan_overview."application/vnd.security.vulnerability.report; version=1.1"')
            
            if [ "$scan_info" != "null" ]; then
                status=$(echo "$scan_info" | jq -r '.scan_status')
                case $status in
                    "Running") running_count=$((running_count + 1)) ;;
                    "Error") error_count=$((error_count + 1)) ;;
                    "Pending") pending_count=$((pending_count + 1)) ;;
                esac
            else
                pending_count=$((pending_count + 1))
            fi
        fi
    done
done

echo ""
echo "📊 Статистика проекта '$PROJECT_NAME':"
echo "  Всего образов: $total_artifacts"
echo "  Отсканировано: $scanned_count"
echo "  Не отсканировано: $unscanned_count"
if [ $unscanned_count -gt 0 ]; then
    echo "    - Выполняется: $running_count"
    echo "    - Ошибки: $error_count"
    echo "    - Ожидает: $pending_count"
fi

if [ $scanned_count -gt 0 ]; then
    echo ""
    echo "🔍 Сводка по уязвимостям:"
    echo "  📊 Всего уязвимостей: $total_vulnerabilities"
    echo "  🔴 Критические: $total_critical"
    echo "  🟠 Высокие: $total_high"
    echo "  🟡 Средние: $total_medium"
    echo "  🟢 Низкие: $total_low"
    echo "  ❓ Неизвестные: $total_unknown"
    echo "  🔧 Исправимые: $total_fixable"
    
    # Определяем общий уровень риска проекта
    if [ $total_critical -gt 0 ]; then
        echo "  ⚠️  Общий уровень риска: 🔴 КРИТИЧЕСКИЙ"
    elif [ $total_high -gt 0 ]; then
        echo "  ⚠️  Общий уровень риска: 🟠 ВЫСОКИЙ"
    elif [ $total_medium -gt 0 ]; then
        echo "  ⚠️  Общий уровень риска: 🟡 СРЕДНИЙ"
    elif [ $total_low -gt 0 ]; then
        echo "  ⚠️  Общий уровень риска: 🟢 НИЗКИЙ"
    else
        echo "  ✅ Общий уровень риска: БЕЗОПАСНЫЙ"
    fi
    
    # Показываем информацию о сканере проекта
    if [ -n "$project_scanner_name" ]; then
        echo ""
        echo "🔍 Сканер проекта: $project_scanner_name $project_scanner_version ($project_scanner_vendor)"
    fi
fi

if [ $unscanned_count -gt 0 ]; then
    echo ""
    echo "💡 Для запуска сканирования используйте:"
    echo "   ./scan_project.sh $PROJECT_NAME --force"
fi

if [ $scanned_count -eq $total_artifacts ] && [ $total_artifacts -gt 0 ]; then
    echo ""
    echo "🎉 Все образы в проекте отсканированы!"
fi
