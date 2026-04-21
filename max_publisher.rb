#!/usr/bin/env ruby
# encoding: utf-8

# MAX Messenger Publisher Module
# Модуль для работы с мессенджером MAX через API (https://dev.max.ru/docs-api)
# Публикация постов в канал

require 'httparty'
require 'json'

class MaxPublisher
  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp].freeze
  VIDEO_EXTENSIONS = %w[.mp4 .mov .avi .wmv].freeze
  
  # Базовый URL API MAX
  BASE_URL = 'https://api.max.ru'
  
  # Эндпоинты API согласно документации https://dev.max.ru/docs-api
  UPLOAD_ENDPOINT = '/uploads'
  MESSAGES_ENDPOINT = '/messages'
  
  attr_reader :config, :access_token, :channel_id
  
  def initialize(config)
    @config = config
    @access_token = config['access_token']
    @channel_id = config['channel_id']
  end
  
  # Публикация поста в канал MAX
  # title: заголовок новости (первая строка txt файла)
  # paragraphs: массив абзацев текста (остальные строки txt файла)
  # logo_path: путь к файлу обложки (может быть nil)
  # images: массив путей к изображениям
  # videos: массив путей к видеофайлам
  def publish_news(title, paragraphs, logo_path, images = [], videos = [])
    puts "\n=== Начало публикации новости в MAX Messenger ==="
    puts "Заголовок: #{title}"
    puts "Канал: #{@channel_id}"
    
    # Проверяем, есть ли текст кроме заголовка
    has_text_content = paragraphs.any? { |p| !p.strip.empty? }
    
    # Проверяем, есть ли видео
    has_videos = videos.any? { |v| File.exist?(v) }
    
    # Формируем текст поста с форматированием
    # Заголовок выделяем жирным шрифтом используя HTML <b>тег</b>
    post_text = build_post_text(title, paragraphs)
    
    # Определяем, какие медиафайлы загружать
    media_to_upload = []
    
    # Если есть только видео и нет текста кроме заголовка - загружаем только видео
    # Изображение с _logo не загружать
    if !has_text_content && has_videos
      puts "✓ Только видео без текста - загружаем только видео (без logo)"
      videos.each do |video_path|
        media_to_upload << { path: video_path, type: :video } if File.exist?(video_path)
      end
    else
      # Иначе загружаем logo первым + остальные медиа
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
    
    # Загружаем все медиафайлы и собираем attachment объекты
    attachments = []
    
    media_to_upload.each_with_index do |media_info, index|
      puts "Загрузка медиафайла #{index + 1}/#{media_to_upload.length}: #{File.basename(media_info[:path])}"
      
      if media_info[:type] == :image
        attachment_obj = upload_image(media_info[:path])
      else
        attachment_obj = upload_video(media_info[:path])
      end
      
      if attachment_obj
        attachments << attachment_obj
      else
        puts "✗ Не удалось загрузить файл: #{media_info[:path]}"
      end
    end
    
    # Публикуем пост
    if attachments.empty? && post_text.strip.empty?
      puts "✗ Ошибка: Нет контента для публикации (ни текста, ни медиа)"
      return { success: false, error: "Нет контента для публикации" }
    end
    
    result = send_message(post_text, attachments)
    
    if result && result[:success]
      puts "\n✓ Пост успешно опубликован в MAX Messenger!"
      puts "URL: #{result[:url]}"
    else
      puts "\n✗ Ошибка при публикации поста в MAX Messenger"
    end
    
    result
  end
  
  private
  
  # Формирование текста поста
  # Заголовок выделяется жирным шрифтом с помощью HTML тега <b>
  # Текст загружается без дополнительного форматирования, между абзацами отступ в строку
  # В конце добавляется футер с ссылкой на канал
  def build_post_text(title, paragraphs)
    text_parts = []
    
    # Первая строка - заголовок, выделенный жирным шрифтом
    unless title.nil? || title.strip.empty?
      text_parts << "<b>#{title.strip}</b>"
    end
    
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
  
  # Загрузка изображения через MAX API
  # Возвращает объект attachment для использования в сообщении
  def upload_image(file_path)
    begin
      filename = File.basename(file_path)
      content_type = case File.extname(filename).downcase
                     when '.jpg', '.jpeg' then 'image/jpeg'
                     when '.png' then 'image/png'
                     when '.gif' then 'image/gif'
                     when '.webp' then 'image/webp'
                     else 'image/jpeg'
                     end
      
      # Загружаем файл напрямую через POST /uploads
      file_data = File.read(file_path)
      
      response = HTTParty.post(
        "#{BASE_URL}#{UPLOAD_ENDPOINT}",
        headers: {
          'Authorization' => "Bearer #{@access_token}"
        },
        body: {
          file: HTTParty::UploadIO.new(file_path, content_type, filename)
        }
      )
      
      if response.code != 200
        puts "✗ Ошибка загрузки файла: #{response.code} - #{response.message}"
        puts "Ответ API: #{response.body}"
        return nil
      end
      
      file_info = response.parsed_response
      file_uuid = file_info['uuid'] || file_info['file_id'] || file_info['id']
      
      puts "✓ Изображение загружено: #{file_uuid}"
      
      # Возвращаем объект attachment для сообщения
      {
        type: 'image',
        uuid: file_uuid
      }
      
    rescue => e
      puts "✗ Ошибка загрузки изображения: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      nil
    end
  end
  
  # Загрузка видео через MAX API
  # Возвращает объект attachment для использования в сообщении
  def upload_video(file_path)
    begin
      filename = File.basename(file_path)
      content_type = 'video/mp4'
      
      # Загружаем файл напрямую через POST /uploads
      response = HTTParty.post(
        "#{BASE_URL}#{UPLOAD_ENDPOINT}",
        headers: {
          'Authorization' => "Bearer #{@access_token}"
        },
        body: {
          file: HTTParty::UploadIO.new(file_path, content_type, filename)
        }
      )
      
      if response.code != 200
        puts "✗ Ошибка загрузки файла: #{response.code} - #{response.message}"
        puts "Ответ API: #{response.body}"
        return nil
      end
      
      file_info = response.parsed_response
      file_uuid = file_info['uuid'] || file_info['file_id'] || file_info['id']
      
      puts "✓ Видео загружено: #{file_uuid}"
      
      # Возвращаем объект attachment для сообщения
      {
        type: 'video',
        uuid: file_uuid
      }
      
    rescue => e
      puts "✗ Ошибка загрузки видео: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      nil
    end
  end
  
  # Отправка сообщения в канал
  # message_text: текст сообщения с HTML форматированием
  # attachments: массив объектов attachments (image, video)
  def send_message(message_text, attachments)
    begin
      # Формируем тело сообщения согласно API MAX
      # POST https://dev.max.ru/docs-api/methods/POST/messages
      payload = {
        channel_id: @channel_id,
        text: message_text
      }
      
      # Добавляем attachments если они есть
      if attachments.any?
        payload[:attachments] = attachments.map do |att|
          {
            type: att[:type],
            uuid: att[:uuid]
          }
        end
      end
      
      response = HTTParty.post(
        "#{BASE_URL}#{MESSAGES_ENDPOINT}",
        headers: {
          'Authorization' => "Bearer #{@access_token}",
          'Content-Type' => 'application/json'
        },
        body: payload.to_json
      )
      
      if response.code != 200
        error_msg = begin
                      response.parsed_response['error'] || response.message
                    rescue
                      response.message
                    end
        puts "✗ Ошибка публикации сообщения: #{response.code} - #{error_msg}"
        return { success: false, error: error_msg }
      end
      
      message_data = response.parsed_response
      message_id = message_data['message_id'] || message_data['id']
      
      # Формируем URL на сообщение в канале
      url = "https://max.ru/#{@channel_id}?m=#{message_id}"
      
      puts "✓ Сообщение опубликовано (ID: #{message_id})"
      { success: true, message_id: message_id, url: url }
      
    rescue => e
      puts "✗ Ошибка отправки сообщения: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      { success: false, error: e.message }
    end
  end
end
