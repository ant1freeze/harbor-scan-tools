#!/usr/bin/env python3
"""
Скрипт для запуска сканирования образов в Harbor Registry
Использует Harbor REST API v2.0 для сканирования уязвимостей
"""

import requests
import json
import sys
import time
import argparse
from typing import List, Dict, Any, Optional
from urllib.parse import quote

class HarborScanner:
    def __init__(self, base_url: str, username: str = "admin", password: str = "Harbor12345"):
        """
        Инициализация клиента Harbor Scanner
        
        Args:
            base_url: Базовый URL Harbor (например, http://localhost:8080)
            username: Имя пользователя (по умолчанию admin)
            password: Пароль (по умолчанию Harbor12345)
        """
        self.base_url = base_url.rstrip('/')
        self.username = username
        self.password = password
        self.session = requests.Session()
        self.session.auth = (username, password)
        
        # Получаем CSRF токен
        self._get_csrf_token()
        
        # Проверяем подключение
        self._test_connection()
    
    def _get_csrf_token(self):
        """Получает CSRF токен от Harbor"""
        try:
            response = self.session.get(f"{self.base_url}/c/login")
            if response.status_code == 200:
                # Извлекаем CSRF токен из HTML
                import re
                csrf_match = re.search(r'name="csrf_token"\s+value="([^"]+)"', response.text)
                if csrf_match:
                    self.csrf_token = csrf_match.group(1)
                    print(f"✅ CSRF токен получен")
                else:
                    print("⚠️  CSRF токен не найден, попробуем без него")
                    self.csrf_token = None
            else:
                print("⚠️  Не удалось получить CSRF токен")
                self.csrf_token = None
        except Exception as e:
            print(f"⚠️  Ошибка получения CSRF токена: {e}")
            self.csrf_token = None
    
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
    
    def get_all_projects(self) -> List[Dict[str, Any]]:
        """Получает все проекты из Harbor"""
        all_projects = []
        page = 1
        
        while True:
            url = f"{self.base_url}/api/v2.0/projects"
            params = {'page': page, 'page_size': 100}
            
            try:
                response = self.session.get(url, params=params)
                response.raise_for_status()
                
                data = response.json()
                if isinstance(data, list):
                    projects = data
                else:
                    projects = data.get('projects', [])
                
                if not projects:
                    break
                
                all_projects.extend(projects)
                page += 1
                
            except requests.exceptions.RequestException as e:
                print(f"❌ Ошибка при получении проектов: {e}")
                break
        
        return all_projects
    
    def get_project_repositories(self, project_name: str) -> List[Dict[str, Any]]:
        """Получает все репозитории в проекте"""
        url = f"{self.base_url}/api/v2.0/projects/{project_name}/repositories"
        
        try:
            response = self.session.get(url)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"❌ Ошибка при получении репозиториев для проекта {project_name}: {e}")
            return []
    
    def get_repository_artifacts(self, project_name: str, repository_name: str) -> List[Dict[str, Any]]:
        """Получает все артефакты в репозитории"""
        repo_name = repository_name.replace(f"{project_name}/", "")
        url = f"{self.base_url}/api/v2.0/projects/{project_name}/repositories/{repo_name}/artifacts"
        
        try:
            response = self.session.get(url)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"❌ Ошибка при получении артефактов для репозитория {repository_name}: {e}")
            return []
    
    def scan_artifact(self, project_name: str, repository_name: str, artifact_digest: str) -> bool:
        """
        Запускает сканирование конкретного артефакта
        
        Args:
            project_name: Имя проекта
            repository_name: Имя репозитория
            artifact_digest: Digest артефакта
            
        Returns:
            True если сканирование запущено успешно
        """
        repo_name = repository_name.replace(f"{project_name}/", "")
        url = f"{self.base_url}/api/v2.0/projects/{project_name}/repositories/{repo_name}/artifacts/{artifact_digest}/scan"
        
        # Данные для запроса
        data = {}
        
        try:
            response = self.session.post(url, json=data)
            print(f"🔍 Ответ API: {response.status_code}")
            if response.status_code == 202:
                print(f"✅ Сканирование запущено для {repository_name}@{artifact_digest[:19]}...")
                return True
            elif response.status_code == 409:
                print(f"⚠️  Сканирование уже выполняется для {repository_name}@{artifact_digest[:19]}...")
                return True
            else:
                print(f"❌ Ошибка запуска сканирования для {repository_name}: {response.status_code}")
                print(f"Ответ: {response.text}")
                print(f"URL: {url}")
                return False
        except requests.exceptions.RequestException as e:
            print(f"❌ Ошибка при запуске сканирования для {repository_name}: {e}")
            return False
    
    def get_scan_report(self, project_name: str, repository_name: str, artifact_digest: str) -> Optional[Dict[str, Any]]:
        """
        Получает отчет о сканировании артефакта
        
        Args:
            project_name: Имя проекта
            repository_name: Имя репозитория
            artifact_digest: Digest артефакта
            
        Returns:
            Отчет о сканировании или None если ошибка
        """
        repo_name = repository_name.replace(f"{project_name}/", "")
        url = f"{self.base_url}/api/v2.0/projects/{project_name}/repositories/{repo_name}/artifacts/{artifact_digest}/scan"
        
        try:
            response = self.session.get(url)
            if response.status_code == 200:
                return response.json()
            else:
                print(f"❌ Ошибка получения отчета для {repository_name}: {response.status_code}")
                return None
        except requests.exceptions.RequestException as e:
            print(f"❌ Ошибка при получении отчета для {repository_name}: {e}")
            return None
    
    def wait_for_scan_completion(self, project_name: str, repository_name: str, artifact_digest: str, timeout: int = 300) -> bool:
        """
        Ожидает завершения сканирования
        
        Args:
            project_name: Имя проекта
            repository_name: Имя репозитория
            artifact_digest: Digest артефакта
            timeout: Таймаут в секундах
            
        Returns:
            True если сканирование завершено успешно
        """
        print(f"⏳ Ожидание завершения сканирования для {repository_name}@{artifact_digest[:19]}...")
        
        start_time = time.time()
        while time.time() - start_time < timeout:
            report = self.get_scan_report(project_name, repository_name, artifact_digest)
            if report:
                status = report.get('status', '')
                if status == 'Success':
                    print(f"✅ Сканирование завершено для {repository_name}@{artifact_digest[:19]}...")
                    return True
                elif status == 'Error':
                    print(f"❌ Ошибка сканирования для {repository_name}@{artifact_digest[:19]}...")
                    return False
                elif status == 'Running':
                    print(f"🔄 Сканирование выполняется... ({int(time.time() - start_time)}с)")
                else:
                    print(f"ℹ️  Статус сканирования: {status}")
            
            time.sleep(5)
        
        print(f"⏰ Таймаут ожидания сканирования для {repository_name}@{artifact_digest[:19]}...")
        return False
    
    def print_scan_report(self, report: Dict[str, Any], repository_name: str, artifact_digest: str):
        """Выводит отчет о сканировании"""
        print(f"\n📊 Отчет о сканировании: {repository_name}@{artifact_digest[:19]}...")
        print("=" * 80)
        
        # Общая информация
        status = report.get('status', 'Unknown')
        print(f"Статус: {status}")
        
        if 'end_time' in report:
            print(f"Время завершения: {report['end_time']}")
        
        # Сводка по уязвимостям
        summary = report.get('summary', {})
        if summary:
            total = summary.get('total', 0)
            high = summary.get('high', 0)
            medium = summary.get('medium', 0)
            low = summary.get('low', 0)
            critical = summary.get('critical', 0)
            unknown = summary.get('unknown', 0)
            
            print(f"\n🔍 Сводка по уязвимостям:")
            print(f"  Всего: {total}")
            print(f"  Критические: {critical}")
            print(f"  Высокие: {high}")
            print(f"  Средние: {medium}")
            print(f"  Низкие: {low}")
            print(f"  Неизвестные: {unknown}")
        
        # Детали уязвимостей
        vulnerabilities = report.get('vulnerabilities', [])
        if vulnerabilities:
            print(f"\n🚨 Детали уязвимостей:")
            for i, vuln in enumerate(vulnerabilities[:10], 1):  # Показываем первые 10
                severity = vuln.get('severity', 'Unknown')
                package = vuln.get('package', 'Unknown')
                version = vuln.get('version', 'Unknown')
                cve_id = vuln.get('id', 'Unknown')
                description = vuln.get('description', 'Нет описания')[:100] + '...' if vuln.get('description') else 'Нет описания'
                
                print(f"  {i:2d}. [{severity}] {cve_id}")
                print(f"      Пакет: {package} {version}")
                print(f"      Описание: {description}")
                print()
            
            if len(vulnerabilities) > 10:
                print(f"  ... и еще {len(vulnerabilities) - 10} уязвимостей")
    
    def scan_all_artifacts_in_project(self, project_name: str, wait_for_completion: bool = False) -> Dict[str, Any]:
        """
        Сканирует все артефакты в проекте
        
        Args:
            project_name: Имя проекта
            wait_for_completion: Ждать завершения сканирования
            
        Returns:
            Статистика сканирования
        """
        print(f"🔍 Сканирование всех артефактов в проекте: {project_name}")
        
        stats = {
            'project': project_name,
            'repositories_scanned': 0,
            'artifacts_scanned': 0,
            'scan_requests_sent': 0,
            'scan_errors': 0
        }
        
        # Получаем репозитории проекта
        repos = self.get_project_repositories(project_name)
        if not repos:
            print(f"❌ Репозитории не найдены в проекте {project_name}")
            return stats
        
        stats['repositories_scanned'] = len(repos)
        
        for repo in repos:
            repo_name = repo.get('name', 'N/A')
            print(f"\n📦 Сканирование репозитория: {repo_name}")
            
            # Получаем артефакты репозитория
            artifacts = self.get_repository_artifacts(project_name, repo_name)
            if not artifacts:
                print(f"  ⚠️  Артефакты не найдены")
                continue
            
            print(f"  Найдено артефактов: {len(artifacts)}")
            
            for artifact in artifacts:
                digest = artifact.get('digest', '')
                if not digest:
                    continue
                
                stats['artifacts_scanned'] += 1
                
                # Запускаем сканирование
                if self.scan_artifact(project_name, repo_name, digest):
                    stats['scan_requests_sent'] += 1
                    
                    if wait_for_completion:
                        if self.wait_for_scan_completion(project_name, repo_name, digest):
                            # Получаем и выводим отчет
                            report = self.get_scan_report(project_name, repo_name, digest)
                            if report:
                                self.print_scan_report(report, repo_name, digest)
                        else:
                            stats['scan_errors'] += 1
                else:
                    stats['scan_errors'] += 1
        
        return stats
    
    def scan_specific_artifact(self, project_name: str, repository_name: str, artifact_digest: str, wait_for_completion: bool = False) -> bool:
        """
        Сканирует конкретный артефакт
        
        Args:
            project_name: Имя проекта
            repository_name: Имя репозитория
            artifact_digest: Digest артефакта
            wait_for_completion: Ждать завершения сканирования
            
        Returns:
            True если сканирование успешно
        """
        print(f"🔍 Сканирование артефакта: {repository_name}@{artifact_digest[:19]}...")
        
        if not self.scan_artifact(project_name, repository_name, artifact_digest):
            return False
        
        if wait_for_completion:
            if self.wait_for_scan_completion(project_name, repository_name, artifact_digest):
                # Получаем и выводим отчет
                report = self.get_scan_report(project_name, repository_name, artifact_digest)
                if report:
                    self.print_scan_report(report, repository_name, artifact_digest)
                return True
            else:
                return False
        
        return True

def main():
    parser = argparse.ArgumentParser(description='Сканирование образов в Harbor Registry')
    parser.add_argument('--url', default='http://localhost:8080', 
                       help='URL Harbor (по умолчанию: http://localhost:8080)')
    parser.add_argument('--username', default='admin', 
                       help='Имя пользователя (по умолчанию: admin)')
    parser.add_argument('--password', default='Harbor12345', 
                       help='Пароль (по умолчанию: Harbor12345)')
    parser.add_argument('--project', 
                       help='Сканировать все артефакты в конкретном проекте')
    parser.add_argument('--repository', 
                       help='Сканировать все артефакты в конкретном репозитории (формат: project/repository)')
    parser.add_argument('--artifact', 
                       help='Сканировать конкретный артефакт (формат: project/repository@digest)')
    parser.add_argument('--all-projects', action='store_true', 
                       help='Сканировать все артефакты во всех проектах')
    parser.add_argument('--wait', action='store_true', 
                       help='Ждать завершения сканирования и показать отчеты')
    parser.add_argument('--timeout', type=int, default=300, 
                       help='Таймаут ожидания сканирования в секундах (по умолчанию: 300)')
    
    args = parser.parse_args()
    
    try:
        # Создаем клиент Harbor Scanner
        scanner = HarborScanner(args.url, args.username, args.password)
        
        if args.artifact:
            # Сканирование конкретного артефакта
            if '@' not in args.artifact:
                print("❌ Ошибка: формат артефакта должен быть project/repository@digest")
                sys.exit(1)
            
            artifact_part, digest = args.artifact.split('@', 1)
            if '/' not in artifact_part:
                print("❌ Ошибка: формат артефакта должен быть project/repository@digest")
                sys.exit(1)
            
            project_name, repo_name = artifact_part.split('/', 1)
            success = scanner.scan_specific_artifact(project_name, repo_name, digest, args.wait)
            
            if success:
                print("✅ Сканирование артефакта завершено успешно")
            else:
                print("❌ Ошибка сканирования артефакта")
                sys.exit(1)
        
        elif args.repository:
            # Сканирование всех артефактов в репозитории
            if '/' not in args.repository:
                print("❌ Ошибка: формат репозитория должен быть project/repository")
                sys.exit(1)
            
            project_name, repo_name = args.repository.split('/', 1)
            artifacts = scanner.get_repository_artifacts(project_name, repo_name)
            
            if not artifacts:
                print(f"❌ Артефакты не найдены в репозитории {args.repository}")
                sys.exit(1)
            
            print(f"🔍 Сканирование {len(artifacts)} артефактов в репозитории {args.repository}")
            
            success_count = 0
            for artifact in artifacts:
                digest = artifact.get('digest', '')
                if digest and scanner.scan_specific_artifact(project_name, repo_name, digest, args.wait):
                    success_count += 1
            
            print(f"✅ Успешно отправлено запросов на сканирование: {success_count}/{len(artifacts)}")
        
        elif args.project:
            # Сканирование всех артефактов в проекте
            stats = scanner.scan_all_artifacts_in_project(args.project, args.wait)
            
            print(f"\n📊 Статистика сканирования проекта {args.project}:")
            print(f"  Репозиториев: {stats['repositories_scanned']}")
            print(f"  Артефактов: {stats['artifacts_scanned']}")
            print(f"  Запросов отправлено: {stats['scan_requests_sent']}")
            print(f"  Ошибок: {stats['scan_errors']}")
        
        elif args.all_projects:
            # Сканирование всех артефактов во всех проектах
            projects = scanner.get_all_projects()
            
            if not projects:
                print("❌ Проекты не найдены")
                sys.exit(1)
            
            print(f"🔍 Сканирование всех артефактов в {len(projects)} проектах")
            
            total_stats = {
                'projects_scanned': 0,
                'repositories_scanned': 0,
                'artifacts_scanned': 0,
                'scan_requests_sent': 0,
                'scan_errors': 0
            }
            
            for project in projects:
                project_name = project.get('name', 'N/A')
                stats = scanner.scan_all_artifacts_in_project(project_name, args.wait)
                
                total_stats['projects_scanned'] += 1
                total_stats['repositories_scanned'] += stats['repositories_scanned']
                total_stats['artifacts_scanned'] += stats['artifacts_scanned']
                total_stats['scan_requests_sent'] += stats['scan_requests_sent']
                total_stats['scan_errors'] += stats['scan_errors']
            
            print(f"\n📊 Общая статистика сканирования:")
            print(f"  Проектов: {total_stats['projects_scanned']}")
            print(f"  Репозиториев: {total_stats['repositories_scanned']}")
            print(f"  Артефактов: {total_stats['artifacts_scanned']}")
            print(f"  Запросов отправлено: {total_stats['scan_requests_sent']}")
            print(f"  Ошибок: {total_stats['scan_errors']}")
        
        else:
            print("❌ Укажите что сканировать: --project, --repository, --artifact или --all-projects")
            parser.print_help()
            sys.exit(1)
        
        print("\n✅ Готово!")
        
    except KeyboardInterrupt:
        print("\n⏹️  Операция прервана пользователем")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Ошибка: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
