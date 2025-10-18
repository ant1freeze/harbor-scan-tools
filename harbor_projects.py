#!/usr/bin/env python3
"""
Скрипт для получения всех проектов из Harbor Registry
Использует Harbor REST API v2.0
"""

import requests
import json
import sys
from urllib.parse import urljoin
import argparse
from typing import List, Dict, Any

class HarborClient:
    def __init__(self, base_url: str, username: str = "admin", password: str = "Harbor12345"):
        """
        Инициализация клиента Harbor
        
        Args:
            base_url: Базовый URL Harbor (например, http://localhost)
            username: Имя пользователя (по умолчанию admin)
            password: Пароль (по умолчанию Harbor12345)
        """
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
    
    def get_all_projects(self, page_size: int = 100) -> List[Dict[str, Any]]:
        """
        Получает все проекты из Harbor
        
        Args:
            page_size: Размер страницы для пагинации
            
        Returns:
            Список всех проектов
        """
        all_projects = []
        page = 1
        
        while True:
            url = f"{self.base_url}/api/v2.0/projects"
            params = {
                'page': page,
                'page_size': page_size,
                'with_detail': 'true'  # Получаем детальную информацию
            }
            
            try:
                response = self.session.get(url, params=params)
                response.raise_for_status()
                
                data = response.json()
                # Harbor API v2.0 возвращает список проектов напрямую
                if isinstance(data, list):
                    projects = data
                else:
                    projects = data.get('projects', [])
                
                if not projects:
                    break
                
                all_projects.extend(projects)
                print(f"📄 Загружена страница {page}, получено проектов: {len(projects)}")
                
                # Проверяем, есть ли еще страницы
                if len(projects) < page_size:
                    break
                    
                page += 1
                
            except requests.exceptions.RequestException as e:
                print(f"❌ Ошибка при получении проектов: {e}")
                break
        
        return all_projects
    
    def get_project_repositories(self, project_name: str) -> List[Dict[str, Any]]:
        """
        Получает все репозитории в проекте
        
        Args:
            project_name: Имя проекта
            
        Returns:
            Список репозиториев в проекте
        """
        url = f"{self.base_url}/api/v2.0/projects/{project_name}/repositories"
        
        try:
            response = self.session.get(url)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"❌ Ошибка при получении репозиториев для проекта {project_name}: {e}")
            return []
    
    def get_repository_artifacts(self, project_name: str, repository_name: str) -> List[Dict[str, Any]]:
        """
        Получает все артефакты (образы) в репозитории
        
        Args:
            project_name: Имя проекта
            repository_name: Имя репозитория
            
        Returns:
            Список артефактов в репозитории
        """
        # Убираем префикс проекта из имени репозитория
        repo_name = repository_name.replace(f"{project_name}/", "")
        url = f"{self.base_url}/api/v2.0/projects/{project_name}/repositories/{repo_name}/artifacts"
        
        try:
            response = self.session.get(url)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"❌ Ошибка при получении артефактов для репозитория {repository_name}: {e}")
            return []
    
    def print_projects_summary(self, projects: List[Dict[str, Any]]):
        """Выводит краткую сводку по проектам"""
        print(f"\n📊 Сводка по проектам:")
        print(f"Всего проектов: {len(projects)}")
        
        if not projects:
            print("Проекты не найдены")
            return
        
        print(f"\n{'№':<3} {'Название':<30} {'Публичный':<10} {'Создан':<20} {'Обновлен':<20}")
        print("-" * 90)
        
        for i, project in enumerate(projects, 1):
            name = project.get('name', 'N/A')
            is_public = 'Да' if project.get('metadata', {}).get('public') == 'true' else 'Нет'
            created = project.get('creation_time', 'N/A')[:19] if project.get('creation_time') else 'N/A'
            updated = project.get('update_time', 'N/A')[:19] if project.get('update_time') else 'N/A'
            
            print(f"{i:<3} {name:<30} {is_public:<10} {created:<20} {updated:<20}")
    
    def print_detailed_projects(self, projects: List[Dict[str, Any]]):
        """Выводит детальную информацию по проектам"""
        print(f"\n📋 Детальная информация по проектам:")
        
        for i, project in enumerate(projects, 1):
            print(f"\n--- Проект {i}: {project.get('name', 'N/A')} ---")
            print(f"ID: {project.get('project_id', 'N/A')}")
            print(f"Название: {project.get('name', 'N/A')}")
            print(f"Публичный: {'Да' if project.get('metadata', {}).get('public') == 'true' else 'Нет'}")
            print(f"Создан: {project.get('creation_time', 'N/A')}")
            print(f"Обновлен: {project.get('update_time', 'N/A')}")
            print(f"Описание: {project.get('metadata', {}).get('description', 'Нет описания')}")
            
            # Получаем репозитории для проекта
            repos = self.get_project_repositories(project.get('name', ''))
            print(f"Репозиториев: {len(repos)}")
            
            if repos:
                print("Репозитории:")
                for repo in repos:  # Показываем все репозитории
                    print(f"  - {repo.get('name', 'N/A')}")
            else:
                print("Репозитории: Нет репозиториев")
    
    def print_repositories_only(self, projects: List[Dict[str, Any]]):
        """Выводит только репозитории для каждого проекта"""
        print(f"\n📦 Репозитории по проектам:")
        
        for project in projects:
            project_name = project.get('name', 'N/A')
            print(f"\n--- Проект: {project_name} ---")
            
            # Получаем репозитории для проекта
            repos = self.get_project_repositories(project_name)
            print(f"Всего репозиториев: {len(repos)}")
            
            if repos:
                for i, repo in enumerate(repos, 1):
                    repo_name = repo.get('name', 'N/A')
                    artifact_count = repo.get('artifact_count', 0)
                    print(f"  {i:2d}. {repo_name} (артефактов: {artifact_count})")
            else:
                print("  Репозитории не найдены")
    
    def print_all_artifacts(self, projects: List[Dict[str, Any]]):
        """Выводит все образы (артефакты) для каждого репозитория"""
        print(f"\n🐳 Образы по репозиториям:")
        
        total_artifacts = 0
        
        for project in projects:
            project_name = project.get('name', 'N/A')
            print(f"\n--- Проект: {project_name} ---")
            
            # Получаем репозитории для проекта
            repos = self.get_project_repositories(project_name)
            
            if not repos:
                print("  Репозитории не найдены")
                continue
            
            for repo in repos:
                repo_name = repo.get('name', 'N/A')
                print(f"\n  📦 Репозиторий: {repo_name}")
                
                # Получаем артефакты для репозитория
                artifacts = self.get_repository_artifacts(project_name, repo_name)
                print(f"    Всего образов: {len(artifacts)}")
                
                if artifacts:
                    for i, artifact in enumerate(artifacts, 1):
                        digest = artifact.get('digest', 'N/A')[:19] + '...' if artifact.get('digest') else 'N/A'
                        size = artifact.get('size', 0)
                        size_mb = size / (1024 * 1024) if size > 0 else 0
                        created = artifact.get('push_time', 'N/A')
                        if created and created != 'N/A':
                            created = created[:19].replace('T', ' ')
                        
                        # Получаем теги
                        tags = artifact.get('tags', [])
                        tag_info = f" (теги: {', '.join([tag.get('name', '') for tag in tags])})" if tags else " (без тегов)"
                        
                        print(f"    {i:2d}. {digest}{tag_info}")
                        print(f"        Размер: {size_mb:.1f} MB, Создан: {created}")
                        
                        # Показываем уязвимости если есть
                        vulnerability_summary = artifact.get('extra_attrs', {}).get('vulnerabilities', {})
                        if vulnerability_summary:
                            total_vulns = vulnerability_summary.get('total', 0)
                            if total_vulns > 0:
                                high = vulnerability_summary.get('summary', {}).get('high', 0)
                                medium = vulnerability_summary.get('summary', {}).get('medium', 0)
                                low = vulnerability_summary.get('summary', {}).get('low', 0)
                                print(f"        Уязвимости: {total_vulns} (H:{high} M:{medium} L:{low})")
                else:
                    print("    Образы не найдены")
                
                total_artifacts += len(artifacts)
        
        print(f"\n📊 Итого образов во всех репозиториях: {total_artifacts}")

def main():
    parser = argparse.ArgumentParser(description='Получение проектов из Harbor Registry')
    parser.add_argument('--url', default='http://localhost:8080', 
                       help='URL Harbor (по умолчанию: http://localhost:8080)')
    parser.add_argument('--username', default='admin', 
                       help='Имя пользователя (по умолчанию: admin)')
    parser.add_argument('--password', default='Harbor12345', 
                       help='Пароль (по умолчанию: Harbor12345)')
    parser.add_argument('--detailed', action='store_true', 
                       help='Показать детальную информацию по проектам')
    parser.add_argument('--repos-only', action='store_true', 
                       help='Показать только репозитории для каждого проекта')
    parser.add_argument('--artifacts', action='store_true', 
                       help='Показать все образы (артефакты) для каждого репозитория')
    parser.add_argument('--output', choices=['json', 'table'], default='table',
                       help='Формат вывода (по умолчанию: table)')
    parser.add_argument('--save', help='Сохранить результат в файл')
    
    args = parser.parse_args()
    
    try:
        # Создаем клиент Harbor
        harbor = HarborClient(args.url, args.username, args.password)
        
        # Получаем все проекты
        print("🔍 Получение проектов из Harbor...")
        projects = harbor.get_all_projects()
        
        if args.output == 'json':
            # Выводим в формате JSON
            result = {
                'harbor_url': args.url,
                'total_projects': len(projects),
                'projects': projects
            }
            output = json.dumps(result, indent=2, ensure_ascii=False)
            print(output)
        else:
            # Выводим в табличном формате
            if args.artifacts:
                harbor.print_all_artifacts(projects)
            elif args.repos_only:
                harbor.print_repositories_only(projects)
            elif args.detailed:
                harbor.print_detailed_projects(projects)
            else:
                harbor.print_projects_summary(projects)
        
        # Сохраняем в файл если указано
        if args.save:
            with open(args.save, 'w', encoding='utf-8') as f:
                if args.output == 'json':
                    f.write(output)
                else:
                    f.write(f"Harbor URL: {args.url}\n")
                    f.write(f"Всего проектов: {len(projects)}\n\n")
                    for i, project in enumerate(projects, 1):
                        f.write(f"{i}. {project.get('name', 'N/A')}\n")
            print(f"💾 Результат сохранен в файл: {args.save}")
        
        print(f"\n✅ Готово! Получено проектов: {len(projects)}")
        
    except KeyboardInterrupt:
        print("\n⏹️  Операция прервана пользователем")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Ошибка: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
