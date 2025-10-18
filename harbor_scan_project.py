#!/usr/bin/env python3
"""
Скрипт для запуска сканирования всех образов в конкретном проекте Harbor
"""

import requests
import json
import sys
import time
import argparse
from typing import List, Dict, Any

class HarborProjectScanner:
    def __init__(self, base_url: str, username: str = "admin", password: str = "Harbor12345"):
        self.base_url = base_url.rstrip('/')
        self.username = username
        self.password = password
        self.session = requests.Session()
        self.session.auth = (username, password)
        
        # Проверяем подключение
        self._test_connection()
    
    def _test_connection(self):
        """Проверяет подключение к Harbor"""
        try:
            response = self.session.get(f"{self.base_url}/api/v2.0/systeminfo")
            if response.status_code == 200:
                print(f"✅ Успешное подключение к Harbor: {self.base_url}")
            else:
                print(f"❌ Ошибка подключения к Harbor: {response.status_code}")
                sys.exit(1)
        except requests.exceptions.RequestException as e:
            print(f"❌ Не удалось подключиться к Harbor: {e}")
            sys.exit(1)
    
    def get_projects(self) -> List[Dict[str, Any]]:
        """Получает список всех проектов"""
        try:
            response = self.session.get(f"{self.base_url}/api/v2.0/projects")
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"❌ Ошибка получения проектов: {e}")
            return []
    
    def get_project_repositories(self, project_name: str) -> List[Dict[str, Any]]:
        """Получает все репозитории в проекте"""
        try:
            response = self.session.get(f"{self.base_url}/api/v2.0/projects/{project_name}/repositories")
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"❌ Ошибка получения репозиториев для проекта {project_name}: {e}")
            return []
    
    def get_repository_artifacts(self, project_name: str, repository_name: str) -> List[Dict[str, Any]]:
        """Получает все артефакты в репозитории"""
        repo_name = repository_name.replace(f"{project_name}/", "")
        try:
            response = self.session.get(f"{self.base_url}/api/v2.0/projects/{project_name}/repositories/{repo_name}/artifacts")
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"❌ Ошибка получения артефактов для репозитория {repository_name}: {e}")
            return []
    
    def get_scan_status(self, project_name: str, repository_name: str, artifact_digest: str) -> Dict[str, Any]:
        """Получает статус сканирования артефакта"""
        repo_name = repository_name.replace(f"{project_name}/", "")
        try:
            response = self.session.get(f"{self.base_url}/api/v2.0/projects/{project_name}/repositories/{repo_name}/artifacts/{artifact_digest}?with_scan_overview=true")
            response.raise_for_status()
            data = response.json()
            scan_overview = data.get('scan_overview', {})
            return scan_overview.get('application/vnd.security.vulnerability.report; version=1.1', {})
        except requests.exceptions.RequestException as e:
            print(f"❌ Ошибка получения статуса сканирования для {repository_name}: {e}")
            return {}
    
    def scan_artifact(self, project_name: str, repository_name: str, artifact_digest: str) -> bool:
        """Запускает сканирование артефакта"""
        repo_name = repository_name.replace(f"{project_name}/", "")
        url = f"{self.base_url}/api/v2.0/projects/{project_name}/repositories/{repo_name}/artifacts/{artifact_digest}/scan"
        
        try:
            headers = {
                'Content-Type': 'application/json',
                'X-Requested-With': 'XMLHttpRequest'
            }
            response = self.session.post(url, json={}, headers=headers)
            
            if response.status_code == 202:
                print(f"✅ Сканирование запущено для {repository_name}@{artifact_digest[:19]}...")
                return True
            elif response.status_code == 409:
                print(f"⚠️  Сканирование уже выполняется для {repository_name}@{artifact_digest[:19]}...")
                return True
            else:
                print(f"❌ Ошибка запуска сканирования для {repository_name}: {response.status_code}")
                return False
        except requests.exceptions.RequestException as e:
            print(f"❌ Ошибка при запуске сканирования для {repository_name}: {e}")
            return False
    
    def scan_project(self, project_name: str, force_rescan: bool = False) -> Dict[str, int]:
        """Сканирует все артефакты в проекте"""
        print(f"🔍 Сканирование всех образов в проекте: {project_name}")
        
        # Проверяем, существует ли проект
        projects = self.get_projects()
        project_exists = any(p.get('name') == project_name for p in projects)
        
        if not project_exists:
            print(f"❌ Проект '{project_name}' не найден!")
            print("Доступные проекты:")
            for project in projects:
                print(f"  - {project.get('name', 'N/A')}")
            return {}
        
        stats = {
            'total_artifacts': 0,
            'new_scans': 0,
            'already_scanned': 0,
            'already_running': 0,
            'errors': 0
        }
        
        print(f"🏗️  Проект: {project_name}")
        
        # Получаем репозитории проекта
        repos = self.get_project_repositories(project_name)
        if not repos:
            print(f"❌ В проекте '{project_name}' нет репозиториев!")
            return stats
        
        for repo in repos:
            repo_name = repo.get('name', 'N/A')
            print(f"\n  📦 Репозиторий: {repo_name}")
            
            # Получаем артефакты репозитория
            artifacts = self.get_repository_artifacts(project_name, repo_name)
            if not artifacts:
                print(f"    ⚠️  В репозитории нет артефактов")
                continue
            
            print(f"    Найдено артефактов: {len(artifacts)}")
            
            for artifact in artifacts:
                digest = artifact.get('digest', '')
                if not digest:
                    continue
                
                stats['total_artifacts'] += 1
                
                # Проверяем статус сканирования
                scan_info = self.get_scan_status(project_name, repo_name, digest)
                
                if scan_info:
                    status = scan_info.get('scan_status', '')
                    
                    if status == 'Success':
                        if not force_rescan:
                            summary = scan_info.get('summary', {})
                            total = summary.get('total', 0)
                            high = summary.get('summary', {}).get('High', 0)
                            medium = summary.get('summary', {}).get('Medium', 0)
                            low = summary.get('summary', {}).get('Low', 0)
                            print(f"    ✅ {repo_name}@{digest[:19]}... - Уже отсканирован (Уязвимостей: {total}, H:{high} M:{medium} L:{low})")
                            stats['already_scanned'] += 1
                            continue
                        else:
                            print(f"    🔄 {repo_name}@{digest[:19]}... - Принудительное пересканирование")
                    elif status == 'Running':
                        print(f"    🔄 {repo_name}@{digest[:19]}... - Уже выполняется")
                        stats['already_running'] += 1
                        continue
                    elif status == 'Error':
                        print(f"    ❌ {repo_name}@{digest[:19]}... - Ошибка сканирования, попробуем еще раз")
                    else:
                        print(f"    ℹ️  {repo_name}@{digest[:19]}... - Статус: {status}")
                else:
                    print(f"    ⚠️  {repo_name}@{digest[:19]}... - Нет данных о сканировании")
                
                # Запускаем сканирование
                if self.scan_artifact(project_name, repo_name, digest):
                    stats['new_scans'] += 1
                else:
                    stats['errors'] += 1
                
                time.sleep(1)  # Небольшая пауза между запросами
        
        return stats

def main():
    parser = argparse.ArgumentParser(description='Сканирование образов в конкретном проекте Harbor')
    parser.add_argument('project', help='Имя проекта для сканирования')
    parser.add_argument('--url', default='http://localhost:8080', 
                       help='URL Harbor (по умолчанию: http://localhost:8080)')
    parser.add_argument('--username', default='admin', 
                       help='Имя пользователя (по умолчанию: admin)')
    parser.add_argument('--password', default='Harbor12345', 
                       help='Пароль (по умолчанию: Harbor12345)')
    parser.add_argument('--force', action='store_true', 
                       help='Принудительное пересканирование уже отсканированных образов')
    
    args = parser.parse_args()
    
    try:
        # Создаем клиент Harbor Scanner
        scanner = HarborProjectScanner(args.url, args.username, args.password)
        
        # Сканируем проект
        stats = scanner.scan_project(args.project, args.force)
        
        if stats:
            print(f"\n📊 Статистика сканирования проекта '{args.project}':")
            print(f"  Всего артефактов: {stats['total_artifacts']}")
            print(f"  Новых сканирований запущено: {stats['new_scans']}")
            print(f"  Уже отсканировано: {stats['already_scanned']}")
            print(f"  Уже выполняется: {stats['already_running']}")
            print(f"  Ошибок: {stats['errors']}")
            
            if stats['new_scans'] > 0:
                print(f"\n💡 Для проверки статуса сканирования используйте:")
                print(f"   ./check_scan_status.sh")
        
        print("\n✅ Готово!")
        
    except KeyboardInterrupt:
        print("\n⏹️  Операция прервана пользователем")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Ошибка: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
