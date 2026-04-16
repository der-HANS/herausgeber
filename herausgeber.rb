#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# Herausgeber - Основная программа публикации новостей
# Принимает путь к директории с файлами как параметр командной строки

require 'yaml'
require 'pathname'
require_relative 'wordpress_publisher'

class Herausgeber
  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp].freeze
  VIDEO_EXTENSIONS = %w[.mp4 .mov .avi .wmv].freeze
  
  attr_reader :content_dir, :config

  def initialize
    @content_dir = nil
    @config = nil
  end

  # Загрузка конфигурации из config.yml
  def load_config
    config_path = File.join(File.dirname(__FILE__), 'config.yml')
    
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

  # Показать меню выбора платформы
  def show_platform_menu
    puts "\n" + "=" * 50
    puts "ВЫБОР ПЛАТФОРМЫ ДЛЯ ПУБЛИКАЦИИ"
    puts "=" * 50
    puts "1. Опубликовать новость на сайт pnisurov.ru"
    puts "0. Выход"
    puts "-" * 50
    print "Выберите опцию: "
    $stdout.flush
    
    choice = STDIN.gets&.strip
    
    case choice
    when '1'
      :wordpress_pnisurov
    when '0', nil
      :exit
    else
      puts "Неверный выбор"
      nil
    end
  end

  # Основной метод запуска
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

    # Показ меню выбора платформы
    platform = show_platform_menu
    
    case platform
    when :wordpress_pnisurov
      publish_to_wordpress(files, text_data)
    when :exit
      puts "Выход из программы"
      return
    else
      puts "Платформа не выбрана"
      return
    end
  end

  # Публикация на WordPress
  def publish_to_wordpress(files, text_data)
    wordpress_config = @config['wordpress']
    
    publisher = WordPressPublisher.new(wordpress_config)
    
    unless publisher.connect
      puts "✗ Не удалось подключиться к WordPress"
      return
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
      puts "\n" + "=" * 50
      puts "✓ НОВОСТЬ УСПЕШНО ОПУБЛИКОВАНА!"
      puts "=" * 50
    else
      puts "\n" + "=" * 50
      puts "✗ ОШИБКА ПРИ ПУБЛИКАЦИИ"
      puts "=" * 50
    end
  end
end

# Запуск программы
if __FILE__ == $PROGRAM_NAME
  app = Herausgeber.new
  app.run
end
