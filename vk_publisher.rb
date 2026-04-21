#!/usr/bin/env ruby
# encoding: utf-8

# VKontakte Publisher Module
# Модуль для работы с VKontakte через API (https://dev.vk.com/ru/method/wall.post)

require 'httparty'
require 'json'

class VKPublisher
  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp].freeze
  VIDEO_EXTENSIONS = %w[.mp4 .mov .avi .wmv].freeze
  
  # Лимит на количество прикрепляемых медиафайлов
  MAX_ATTACHMENTS = 10
  
  attr_reader :config, :access_token, :group_id
  
  def initialize(config)
    @config = config
    @access_token = config['access_token']
    @group_id = config['group_id']
  end
  
  # Публикация поста на стене группы VK
  # title: заголовок новости (первая строка txt файла)
  # paragraphs: массив абзацев текста (остальные строки txt файла)
  # logo_path: путь к файлу обложки (может быть nil)
  # images: массив путей к изображениям
  # videos: массив путей к видеофайлам
  def publish_news(title, paragraphs, logo_path, images = [], videos = [])
    puts "\n=== Начало публикации новости в VKontakte ==="
    puts "Заголовок: #{title}"
    
    # Проверяем, есть ли текст кроме заголовка
    has_text_content = paragraphs.any? { |p| !p.strip.empty? }
    
    # Проверяем, есть ли видео
    has_videos = videos.any? { |v| File.exist?(v) }
    
    # Формируем текст поста
    post_text = build_post_text(title, paragraphs)
    
    # Определяем, какие медиафайлы загружать
    media_to_upload = []
    
    # Если есть только видео и нет текста кроме заголовка - загружаем только видео
    if !has_text_content && has_videos
      puts "✓ Только видео без текста - загружаем только видео"
      videos.each do |video_path|
        media_to_upload << { path: video_path, type: :video } if File.exist?(video_path)
      end
    else
      # Иначе загружаем logo первым + остальные медиа (до 10 всего)
      if logo_path && File.exist?(logo_path)
        media_to_upload << { path: logo_path, type: :image, is_logo: true }
      end
      
      # Добавляем остальные изображения
      images.each do |img_path|
        media_to_upload << { path: img_path, type: :image } if File.exist?(img_path)
      end
      
      # Добавляем видео
      videos.each do |video_path|
        media_to_upload << { path: video_path, type: :video } if File.exist?(video_path)
      end
    end
    
    # Обрезаем до MAX_ATTACHMENTS, но logo всегда первый
    if media_to_upload.length > MAX_ATTACHMENTS
      # Сохраняем logo если он есть
      logo_item = media_to_upload.find { |m| m[:is_logo] }
      other_items = media_to_upload.reject { |m| m[:is_logo] }
      
      # Берем первые (MAX_ATTACHMENTS - 1) элементов из остальных
      other_items = other_items.first(MAX_ATTACHMENTS - 1) if logo_item
      
      media_to_upload = logo_item ? [logo_item] + other_items : other_items.first(MAX_ATTACHMENTS)
      
      puts "⚠ Превышен лимит #{MAX_ATTACHMENTS} медиафайлов, обрезано до #{media_to_upload.length}"
    end
    
    # Загружаем все медиафайлы и собираем attachment строки
    attachments = []
    
    media_to_upload.each_with_index do |media_info, index|
      puts "Загрузка медиафайла #{index + 1}/#{media_to_upload.length}: #{File.basename(media_info[:path])}"
      
      if media_info[:type] == :image
        attachment_str = upload_image(media_info[:path])
      else
        attachment_str = upload_video(media_info[:path])
      end
      
      if attachment_str
        attachments << attachment_str
      else
        puts "✗ Не удалось загрузить файл: #{media_info[:path]}"
      end
    end
    
    # Публикуем пост
    if attachments.empty? && post_text.strip.empty?
      puts "✗ Ошибка: Нет контента для публикации (ни текста, ни медиа)"
      return { success: false, error: "Нет контента для публикации" }
    end
    
    result = post_to_wall(post_text, attachments)
    
    if result && result[:success]
      puts "\n✓ Пост успешно опубликован в VKontakte!"
      puts "URL: #{result[:url]}"
    else
      puts "\n✗ Ошибка при публикации поста в VKontakte"
    end
    
    result
  end
  
  private
  
  # Формирование текста поста
  # Текст загружается без форматирования, между абзацами отступ в строку
  # В конце добавляется футер с ссылкой на MAX
  def build_post_text(title, paragraphs)
    text_parts = []
    
    # Первая строка - заголовок
    text_parts << title.strip unless title.nil? || title.strip.empty?
    
    # Добавляем абзацы с отступами (пустая строка между абзацами)
    paragraphs.each do |paragraph|
      next if paragraph.strip.empty?
      text_parts << ""  # Пустая строка - отступ
      text_parts << paragraph.strip
    end
    
    # Добавляем футер
    footer = "\n------------------------------------------------\nБольше новостей — в нашем канале в мессенджере MAX: https://max.ru/id3430030612_gos"
    text_parts << footer
    
    text_parts.join("\n")
  end
  
  # Загрузка изображения через VK API
  # Возвращает строку формата "photo{owner_id}_{photo_id}"
  def upload_image(file_path)
    begin
      filename = File.basename(file_path)
      
      # Шаг 1: Получаем URL для загрузки
      upload_url_response = HTTParty.get(
        "https://api.vk.com/method/photos.getWallUploadServer",
        query: {
          access_token: @access_token,
          v: '5.131',
          group_id: @group_id
        },
        debug_output: $stdout
      )
   
  pp upload_url_response

      if upload_url_response.parsed_response['error']
        puts "✗ Ошибка получения URL загрузки: #{upload_url_response.parsed_response['error']['error_msg']}"
        return nil
      end
      
      upload_url = upload_url_response.parsed_response['response']['upload_url']
      
      # Шаг 2: Загружаем файл
      file_data = File.read(file_path)
      upload_response = HTTParty.post(
        upload_url,
        body: { file: HTTParty::Multipart::File.new(file_data, filename: filename, content_type: 'image/jpeg') }
      )
      
      # Шаг 3: Сохраняем фото
      save_response = HTTParty.post(
        "https://api.vk.com/method/photos.saveWallPhoto",
        query: {
          access_token: @access_token,
          v: '5.131',
          group_id: @group_id,
          photo: upload_response.parsed_response['photo'],
          server: upload_response.parsed_response['server'],
          hash: upload_response.parsed_response['hash']
        }
      )
      
      if save_response.parsed_response['error']
        puts "✗ Ошибка сохранения фото: #{save_response.parsed_response['error']['error_msg']}"
        return nil
      end
      
      photo = save_response.parsed_response['response'][0]
      owner_id = photo['owner_id']
      photo_id = photo['id']
      
      puts "✓ Изображение загружено: photo#{owner_id}_#{photo_id}"
      "photo#{owner_id}_#{photo_id}"
      
    rescue => e
      puts "✗ Ошибка загрузки изображения: #{e.message}"
      nil
    end
  end
  
  # Загрузка видео через VK API
  # Возвращает строку формата "video{owner_id}_{video_id}"
  def upload_video(file_path)
    begin
      filename = File.basename(file_path)
      filesize = File.size(file_path)
      
      # Шаг 1: Создаем запись видео и получаем URL для загрузки
      create_response = HTTParty.post(
        "https://api.vk.com/method/video.save",
        query: {
          access_token: @access_token,
          v: '5.131',
          group_id: @group_id,
          name: filename,
          video_file_size: filesize
        }
      )
      
      if create_response.parsed_response['error']
        puts "✗ Ошибка создания видео: #{create_response.parsed_response['error']['error_msg']}"
        return nil
      end
      
      upload_url = create_response.parsed_response['response']['upload_url']
      video_id = create_response.parsed_response['response']['video_id']
      owner_id = create_response.parsed_response['response']['owner_id']
      
      # Шаг 2: Загружаем файл
      file_data = File.read(file_path)
      upload_response = HTTParty.post(
        upload_url,
        body: { file: HTTParty::Multipart::File.new(file_data, filename: filename, content_type: 'video/mp4') }
      )
      
      puts "✓ Видео загружено: video#{owner_id}_#{video_id}"
      "video#{owner_id}_#{video_id}"
      
    rescue => e
      puts "✗ Ошибка загрузки видео: #{e.message}"
      nil
    end
  end
  
  # Публикация поста на стене
  # message: текст поста
  # attachments: массив строк attachments (photo, video, etc.)
  def post_to_wall(message, attachments)
    begin
      # Формируем строку attachments через запятую
      attachments_str = attachments.join(',')
      
      params = {
        access_token: @access_token,
        v: '5.131',
        owner_id: "-#{@group_id}",  # Отрицательный ID для группы
        from_group: 1,              # Публикация от имени группы
        message: message,
        primary_attachments_mode: 'grid'  # Режим отображения вложений
      }
      
      params[:attachment] = attachments_str unless attachments_str.empty?
      
      response = HTTParty.post(
        "https://api.vk.com/method/wall.post",
        query: params
      )
      
      if response.parsed_response['error']
        error_msg = response.parsed_response['error']['error_msg']
        puts "✗ Ошибка публикации поста: #{error_msg}"
        return { success: false, error: error_msg }
      end
      
      post_id = response.parsed_response['response']['post_id']
      url = "https://vk.com/public#{@group_id}?w=wall-#{@group_id}_#{post_id}"
      
      puts "✓ Пост опубликован (ID: #{post_id})"
      { success: true, post_id: post_id, url: url }
      
    rescue => e
      puts "✗ Ошибка публикации поста: #{e.message}"
      { success: false, error: e.message }
    end
  end
end
