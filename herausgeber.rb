#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# Herausgeber - Основная программа публикации новостей
# Принимает путь к директории с файлами как параметр командной строки

require 'yaml'
require 'pathname'
require_relative 'wordpress_publisher'
require_relative 'vk_publisher'

class Herausgeber
  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp].freeze
  VIDEO_EXTENSIONS = %w[.mp4 .mov .avi .wmv].freeze
  
  attr_reader :content_dir, :config, :publications

  def initialize
    @content_dir = nil
    @config = nil
    @publications = []  # Массив для отслеживания всех публикаций
  end

  # Загрузка конфигурации из config.yml
  def load_config
    config_path = File.join(File.dirname(__FILE__), '../config.yml')
    
    unless File.exist?(config_path)
      puts "✗ Ошибка: Файл конфигурации config.yml не найден"
      puts "Создайте файл config.yml с параметрами подключения к WordPress"
      return false
    end

    begin
      @config = YAML.load_file(config_path)
      
      unless @config && @config['wordpress']
        puts "✗ Ошибка: Неверный формат файла config.yml"
        return false
      end

      wordpress_config = @config['wordpress']
      required_fields = ['host', 'username', 'password']
      
      required_fields.each do |field|
        unless wordpress_config[field]
          puts "✗ Ошибка: В config.yml отсутствует поле '#{field}'"
          return false
        end
      end

      puts "✓ Конфигурация загружена"
      true
    rescue => e
      puts "✗ Ошибка чтения config.yml: #{e.message}"
      false
    end
  end

  # Определение директории с контентом
  def determine_content_dir
    # Если передан параметр командной строки - используем его
    if ARGV.length >= 1
      @content_dir = File.expand_path(ARGV[0])
    else
      # Иначе используем текущую директорию
      @content_dir = Dir.pwd
    end

    unless Dir.exist?(@content_dir)
      puts "✗ Ошибка: Директория '#{@content_dir}' не существует"
      return false
    end

    puts "✓ Директория с контентом: #{@content_dir}"
    true
  end

  # Сканирование директории и поиск файлов
  def scan_directory
    files = Dir.entries(@content_dir).select { |f| File.file?(File.join(@content_dir, f)) }
    
    # Поиск обложки (файл с "_logo." в имени)
    logo_files = files.select { |f| f.include?('_logo.') && IMAGE_EXTENSIONS.any? { |ext| f.downcase.end_with?(ext) } }
    
    # Поиск текстового файла
    txt_files = files.select { |f| f.downcase.end_with?('.txt') }
    
    # Проверка единственности обложки
    if logo_files.empty?
      puts "✗ Ошибка: Не найдено изображение-обложка (файл с '_logo.' в имени)"
      return nil
    elsif logo_files.length > 1
      puts "✗ Ошибка: Найдено несколько файлов-обложек: #{logo_files.join(', ')}"
      puts "Требуется единственный экземпляр файла с '_logo.' в имени"
      return nil
    end
    
    # Проверка единственности txt файла
    if txt_files.empty?
      puts "✗ Ошибка: Не найден текстовый файл (*.txt)"
      return nil
    elsif txt_files.length > 1
      puts "✗ Ошибка: Найдено несколько текстовых файлов: #{txt_files.join(', ')}"
      puts "Требуется единственный экземпляр *.txt файла"
      return nil
    end

    # Сбор остальных изображений и видео
    other_images = files.select do |f|
      IMAGE_EXTENSIONS.any? { |ext| f.downcase.end_with?(ext) } && !f.include?('_logo.')
    end
    
    videos = files.select do |f|
      VIDEO_EXTENSIONS.any? { |ext| f.downcase.end_with?(ext) }
    end

    {
      logo: File.join(@content_dir, logo_files.first),
      txt: File.join(@content_dir, txt_files.first),
      images: other_images.map { |f| File.join(@content_dir, f) },
      videos: videos.map { |f| File.join(@content_dir, f) }
    }
  end

  # Чтение и парсинг текстового файла
  def parse_txt_file(txt_path)
    begin
      lines = File.readlines(txt_path, encoding: 'UTF-8').map(&:chomp)
      
      if lines.empty?
        puts "✗ Ошибка: Текстовый файл пуст"
        return nil
      end

      title = lines.first.strip
      
      # Остальные строки - абзацы (пропускаем пустые в начале)
      paragraphs = lines[1..-1] || []
      
      {
        title: title,
        paragraphs: paragraphs
      }
    rescue => e
      puts "✗ Ошибка чтения текстового файла: #{e.message}"
      nil
    end
  end

  # Показать меню выбора платформы (циклическое)
  def show_platform_menu
    puts "\n" + "=" * 50
    puts "ВЫБОР ПЛАТФОРМЫ ДЛЯ ПУБЛИКАЦИИ"
    puts "=" * 50
    puts "1. Опубликовать новость на сайт pnisurov.ru"
    puts "2. Опубликовать новость в VKontakte (vk.com)"
    puts "0. Завершить работу и показать отчет"
    puts "-" * 50
    print "Выберите опцию: "
    $stdout.flush
    
    choice = STDIN.gets&.strip
    
    case choice
    when '1'
      :wordpress_pnisurov
    when '2'
      :vkontakte
    when '0', nil
      :exit
    else
      puts "Неверный выбор"
      nil
    end
  end

  # Вывод отчета о всех публикациях
  def print_report(news_title)
    puts "\n" + "=" * 80
    puts "Опубликовал новостной пост «#{news_title}»"
    puts "-" * 80
    
    wordpress_url = nil
    vk_url = nil
    
    @publications.each do |pub|
      case pub[:platform]
      when :wordpress
        wordpress_url = pub[:url]
      when :vkontakte
        vk_url = pub[:url]
      end
    end
    
    # [1] Ссылка на WordPress
    if wordpress_url
      puts "[1] Ссылка на публикацию информации на Сайте учреждения ГБССУ СО ГПВИ «Суровикинский ДСО» (https://www.pnisurov.ru/ ): #{wordpress_url}"
    else
      puts "[1] Ссылка на публикацию информации на Сайте учреждения ГБССУ СО ГПВИ «Суровикинский ДСО» (https://www.pnisurov.ru/ ): не опубликовано"
    end
    
    # [2] Ссылка на Одноклассники (пока используем URL из VK, так как это одна связь)
    if vk_url
      puts "[2] Ссылка на публикацию информации в госпаблике учреждения ГБССУ СО ГПВИ «Суровикинский ДСО» в социальной сети Одноклассники (https://ok.ru/pnisurov ): #{vk_url}"
    else
      puts "[2] Ссылка на публикацию информации в госпаблике учреждения ГБССУ СО ГПВИ «Суровикинский ДСО» в социальной сети Одноклассники (https://ok.ru/pnisurov ): не опубликовано"
    end
    
    # [3] Ссылка на ВКонтакте
    if vk_url
      puts "[3] Ссылка на публикацию информации в госпаблике учреждения ГБССУ СО ГПВИ «Суровикинский ДСО» в социальной сети Вконтакте (https://vk.com/pnisurov ): #{vk_url}"
    else
      puts "[3] Ссылка на публикацию информации в госпаблике учреждения ГБССУ СО ГПВИ «Суровикинский ДСО» в социальной сети Вконтакте (https://vk.com/pnisurov ): не опубликовано"
    end
    
    # [4] Ссылка на volganet.ru
    puts "[4] Ссылка на публикацию информации на странице учреждения ГБССУ СО ГПВИ «Суровикинский ДСО» на официальном портале Поставщиков социальных услуг Волгоградской области (https://442fz.volganet.ru/025016/ ): не опубликовано"
    
    # [5] Ссылка на MAX
    puts "[5] Ссылка на публикацию информации в официальной группе учреждения ГБССУ СО ГПВИ «Суровикинский ДСО» в Национальном мессенджере MAX (https://max.ru/id3430030612_gos ): не опубликовано"
    
    puts "=" * 80
  end

  # Основной метод запуска (циклический)
  def run
    puts "=" * 50
    puts "HERAUSGEBER - Система публикации новостей"
    puts "=" * 50

    # Загрузка конфигурации
    return unless load_config

    # Определение директории
    return unless determine_content_dir

    # Сканирование директории
    files = scan_directory
    return unless files

    puts "\n✓ Найденные файлы:"
    puts "  Обложка: #{File.basename(files[:logo])}"
    puts "  Текст: #{File.basename(files[:txt])}"
    puts "  Изображения: #{files[:images].length} шт."
    puts "  Видео: #{files[:videos].length} шт."

    # Парсинг текстового файла
    text_data = parse_txt_file(files[:txt])
    return unless text_data

    puts "\n✓ Данные из текстового файла:"
    puts "  Заголовок: #{text_data[:title]}"
    puts "  Абзацев: #{text_data[:paragraphs].length}"

    # Циклическое меню выбора платформы
    loop do
      platform = show_platform_menu
      
      case platform
      when :wordpress_pnisurov
        result = publish_to_wordpress(files, text_data)
        if result && result[:success]
          @publications << { platform: :wordpress, url: result[:url], title: text_data[:title] }
          puts "\n✓ Публикация на WordPress выполнена успешно!"
        end
      when :vkontakte
        result = publish_to_vkontakte(files, text_data)
        if result && result[:success]
          @publications << { platform: :vkontakte, url: result[:url], title: text_data[:title] }
          puts "\n✓ Публикация в VKontakte выполнена успешно!"
        end
      when :exit
        # Вывод отчета и завершение
        print_report(text_data[:title])
        puts "\nЗавершение работы программы"
        return
      else
        puts "Платформа не выбрана, попробуйте снова"
      end
    end
  end

  # Публикация на WordPress
  def publish_to_wordpress(files, text_data)
    wordpress_config = @config['wordpress']
    
    publisher = WordPressPublisher.new(wordpress_config)
    
    unless publisher.connect
      puts "✗ Не удалось подключиться к WordPress"
      return { success: false, error: "Не удалось подключиться к WordPress" }
    end

    # Публикация новости
    result = publisher.publish_news(
      text_data[:title],
      text_data[:paragraphs],
      files[:logo],
      files[:images],
      files[:videos]
    )

    if result && result[:success]
      # Формируем URL поста на WordPress
      post_url = "#{@config['wordpress']['host'].gsub('xmlrpc.php', '').chomp('/')}?p=#{result[:post_id]}"
      result[:url] = post_url
    end
    
    result
  end
  
  # Публикация в VKontakte
  def publish_to_vkontakte(files, text_data)
    vk_config = @config['vkontakte']
    
    unless vk_config && vk_config['access_token'] && vk_config['group_id']
      puts "✗ Ошибка: В config.yml отсутствуют настройки для VKontakte (access_token, group_id)"
      return { success: false, error: "Отсутствуют настройки VKontakte" }
    end
    
    publisher = VKPublisher.new(vk_config)
    
    # Публикация новости
    result = publisher.publish_news(
      text_data[:title],
      text_data[:paragraphs],
      files[:logo],
      files[:images],
      files[:videos]
    )
    
    result
  end
end

# Запуск программы
if __FILE__ == $PROGRAM_NAME
  app = Herausgeber.new
  app.run
end
