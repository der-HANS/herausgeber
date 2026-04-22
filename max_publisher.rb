#!/usr/bin/env ruby
# encoding: utf-8

# MAX Messenger Publisher Module
# Модуль для работы с мессенджером MAX через API (https://dev.max.ru/docs-api)
# Публикация постов в канал

require 'httparty'
require 'json'

class MaxPublisher
  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp].freeze
  VIDEO_EXTENSIONS = %w[.mp4 .mov .avi .wmv .mkv].freeze
  
  # Базовый URL API MAX
  BASE_URL = 'https://platform-api.max.ru'
  
  # Эндпоинты API согласно документации https://dev.max.ru/docs-api
  UPLOAD_ENDPOINT = '/uploads'
  MESSAGES_ENDPOINT = '/messages'
  
  attr_reader :config, :access_token, :channel_id
  
  def initialize(config)
    @config = config
    @access_token = config['access_token']
    @channel_id = config['channel_id']
  end
  
  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
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
  
  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
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
    
    # # Добавляем футер
    # footer = "\n------------------------------------------------\nБольше новостей — в нашем канале в мессенджере MAX: https://max.ru/id3430030612_gos"
    # text_parts << footer
    
    text_parts.join("\n")
  end
  
  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
   # Загрузка изображения через MAX API
   # Возвращает объект attachment для использования в сообщении
   def upload_image(file_path)
     begin
       filename = File.basename(file_path)
       
       # Шаг 1: Получаем URL для загрузки
       upload_response = HTTParty.post(
         "#{BASE_URL}#{UPLOAD_ENDPOINT}?type=image",
         headers: {
           'Authorization' => "#{@access_token}"
         }
       )

       if upload_response.code != 200
         puts "✗ Ошибка получения URL для загрузки: #{upload_response.code} - #{upload_response.message}"
         puts "Ответ API: #{upload_response.body}"
         return nil
       end
       
       upload_data = upload_response.parsed_response
       upload_url = upload_data['url']

       unless upload_url
         puts "✗ Не получен URL для загрузки в ответе API"
         puts "Ответ API: #{upload_response.body}"
         return nil
       end
       
       # Шаг 2: Загружаем файл по полученному URL
       file_data = File.open(file_path)
       content_type = case File.extname(filename).downcase
                      when '.jpg', '.jpeg' then 'image/jpeg'
                      when '.png' then 'image/png'
                      when '.gif' then 'image/gif'
                      when '.webp' then 'image/webp'
                      else 'image/jpeg'
                      end

       upload_file_response = HTTParty.post(
         upload_url, 
         {
            headers: {
              'Authorization' => "#{@access_token}",
              'Content-Type' => content_type
            },
            body: { data: file_data }
         }
       )

       if upload_file_response.code != 200
         puts "✗ Ошибка загрузки файла: #{upload_file_response.code} - #{upload_file_response.message}"
         puts "Ответ API: #{upload_file_response.body}"
         return nil
       end
       
       file_info = upload_file_response.parsed_response
       file_uuid = file_info["photos"].values.first["token"]

       puts "✓ Изображение загружено: #{file_uuid}"
       
       # Возвращаем объект attachment для сообщения
       {
         type: 'image',
         payload: {
           token: file_uuid
         }
       }

       
     rescue => e
       puts "✗ Ошибка загрузки изображения: #{e.message}"
       puts e.backtrace.first(5).join("\n")
       nil
     end
   end
  
   #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
   # Загрузка видео через MAX API
   # Возвращает объект attachment для использования в сообщении
   def upload_video(file_path)
     begin
      #  filename = File.basename(file_path)
       
       # Шаг 1: Получаем URL для загрузки
       upload_response = HTTParty.post(
         "#{BASE_URL}#{UPLOAD_ENDPOINT}?type=video",
         headers: {
           'Authorization' => "#{@access_token}"
         }
       )

       if upload_response.code != 200
         puts "✗ Ошибка получения URL для загрузки: #{upload_response.code} - #{upload_response.message}"
         puts "Ответ API: #{upload_response.body}"
         return nil
       end
       
       upload_data = upload_response.parsed_response
       upload_url = upload_data['url']

       # Для видео токен приходит в ответе сразу до загрузки файла
       file_token = upload_data["token"]

       unless upload_url
         puts "✗ Не получен URL для загрузки в ответе API"
         puts "Ответ API: #{upload_response.body}"
         return nil
       end
       
        # Шаг 2: Загружаем файл по полученному URL
        filename = File.basename(file_path)
        content_type = case File.extname(filename).downcase
                       when '.mp4' then 'video/mp4'
                       when '.mov' then 'video/quicktime'
                       when '.avi' then 'video/x-msvideo'
                       when '.wmv' then 'video/x-ms-wmv'
                       when '.mkv' then 'video/x-matroska'
                       else 'video/mp4' # default fallback
                       end
        upload_file_response = HTTParty.post(
          upload_url,
          {
           headers: {
             'Authorization' => "#{@access_token}",
             'Content-Type' => content_type
           },
           body: { data: File.open(file_path) }
          }
        )

       if upload_file_response.code != 200 
         puts "✗ Ошибка загрузки файла: #{upload_file_response.code} - #{upload_file_response.message}"
         puts "Ответ API: #{upload_file_response.body}"
         return nil
       end
       
       puts "✓ Видео загружено: #{file_token}"
       
       # Возвращаем объект attachment для сообщения
       {
         type: 'video',
         payload: {
           token: file_token
         }
       }
       
     rescue => e
       puts "✗ Ошибка загрузки видео: #{e.message}"
       puts e.backtrace.first(5).join("\n")
       nil
     end
   end
  
   #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
   # Отправка сообщения в канал
   # message_text: текст сообщения с HTML форматированием
   # attachments: массив объектов attachments (image, video)
   def send_message(message_text, attachments)
     begin
       # Формируем тело сообщения согласно API MAX
       # POST https://dev.max.ru/docs-api/methods/POST/messages
       payload = {
          text: message_text,
          disable_link_preview: true,
          format: "html"
       }
       
       # Добавляем attachments если они есть
       if attachments.any?
         payload[:attachments] = attachments.map do |att|
           {
             type: att[:type],
             payload: att[:payload] || { uuid: att[:uuid] }
           }
         end
       end
       
       response = HTTParty.post(
         "#{BASE_URL}#{MESSAGES_ENDPOINT}?chat_id=#{@channel_id}",
         headers: {
           'Authorization' => "#{@access_token}",
           'Content-Type' => 'application/json'
         },
         body: payload.to_json
         #debug_output: $stdout
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

       # Формируем URL на сообщение в канале
       url = message_data["message"]["url"]
       
       puts "✓ Сообщение опубликовано (URL: #{url})"
       { success: true, url: url }
       
     rescue => e
       puts "✗ Ошибка отправки сообщения: #{e.message}"
       puts e.backtrace.first(5).join("\n")
       { success: false, error: e.message }
     end
   end
end
