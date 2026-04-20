#!/usr/bin/env ruby
# encoding: utf-8

# Odnoklassniki Publisher Module
# Модуль для работы с Одноклассниками через API (https://apiok.ru/dev/methods/rest/mediatopic/mediatopic.post)

require 'httparty'
require 'json'

class OKPublisher
  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp].freeze
  VIDEO_EXTENSIONS = %w[.mp4 .mov .avi .wmv].freeze
  
  # Лимит на количество прикрепляемых медиафайлов
  MAX_ATTACHMENTS = 10
  
  attr_reader :config, :access_token, :group_id, :application_key, :application_secret
  
  def initialize(config)
    @config = config
    @access_token = config['access_token']
    @group_id = config['group_id']
    @application_key = config['application_key']
    @application_secret = config['application_secret']
  end
  
  # Публикация поста в группе OK
  # title: заголовок новости (первая строка txt файла)
  # paragraphs: массив абзацев текста (остальные строки txt файла)
  # logo_path: путь к файлу обложки (может быть nil)
  # images: массив путей к изображениям
  # videos: массив путей к видеофайлам
  def publish_news(title, paragraphs, logo_path, images = [], videos = [])
    puts "\n=== Начало публикации новости в Одноклассниках ==="
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
      puts "✓ Только видео без текста - загружаем только видео (logo не загружается)"
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
    
    # Публикуем пост через mediatopic.post
    if attachments.empty? && post_text.strip.empty?
      puts "✗ Ошибка: Нет контента для публикации (ни текста, ни медиа)"
      return { success: false, error: "Нет контента для публикации" }
    end
    
    result = post_to_mediatopic(post_text, attachments)
    
    if result && result[:success]
      puts "\n✓ Пост успешно опубликован в Одноклассниках!"
      puts "URL: #{result[:url]}"
    else
      puts "\n✗ Ошибка при публикации поста в Одноклассниках"
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
  
  # Подпись запроса для OK API
  # https://apiok.ru/dev/methods/rest/signing
  def sign_request(params)
    # Сортируем параметры по алфавиту
    sorted_params = params.sort_by { |k, _| k.to_s }
    
    # Формируем строку для подписи: параметр=значение&...
    sig_string = sorted_params.map { |k, v| "#{k}=#{v}" }.join('')
    
    # Вычисляем MD5 хеш от строки + application_secret
    digest = OpenSSL::Digest::MD5.hexdigest(sig_string + @application_secret)
    digest
  end
  
  # Загрузка изображения через OK API
  # Возвращает строку формата "photo:{photo_id}"
  def upload_image(file_path)
    begin
      filename = File.basename(file_path)
      
      # Шаг 1: Получаем URL для загрузки через photos.getUploadUrl
      params = {
        application_key: @application_key,
        method: 'photos.getUploadUrl',
        format: 'json',
        access_token: @access_token
      }
      params[:sig] = sign_request(params)
      
      response = HTTParty.get("https://apiok.ru/fb.do", query: params)
      
      if response.parsed_response.is_a?(Hash) && response.parsed_response['error_code']
        puts "✗ Ошибка получения URL загрузки: #{response.parsed_response['error_msg']}"
        return nil
      end
      
      upload_url = response.parsed_response['uploadUrl']
      photo_id = response.parsed_response['photoId']
      
      # Шаг 2: Загружаем файл
      file_data = File.read(file_path)
      content_type = case File.extname(filename).downcase
                     when '.jpg', '.jpeg' then 'image/jpeg'
                     when '.png' then 'image/png'
                     when '.gif' then 'image/gif'
                     when '.webp' then 'image/webp'
                     else 'image/jpeg'
                     end
      
      upload_response = HTTParty.post(
        upload_url,
        body: { file: HTTParty::Multipart::File.new(file_data, filename: filename, content_type: content_type) }
      )
      
      # После загрузки фото нужно сохранить через photos.save
      save_params = {
        application_key: @application_key,
        method: 'photos.save',
        format: 'json',
        access_token: @access_token,
        photoId: photo_id
      }
      save_params[:sig] = sign_request(save_params)
      
      save_response = HTTParty.post("https://apiok.ru/fb.do", query: save_params)
      
      if save_response.parsed_response.is_a?(Hash) && save_response.parsed_response['error_code']
        puts "✗ Ошибка сохранения фото: #{save_response.parsed_response['error_msg']}"
        return nil
      end
      
      saved_photo_id = save_response.parsed_response['photoId']
      
      puts "✓ Изображение загружено: photo:#{saved_photo_id}"
      "photo:#{saved_photo_id}"
      
    rescue => e
      puts "✗ Ошибка загрузки изображения: #{e.message}"
      nil
    end
  end
  
  # Загрузка видео через OK API
  # Возвращает строку формата "video:{video_id}"
  def upload_video(file_path)
    begin
      filename = File.basename(file_path)
      filesize = File.size(file_path)
      
      # Шаг 1: Создаем запись видео и получаем URL для загрузки через video.getUploadUrl
      params = {
        application_key: @application_key,
        method: 'video.getUploadUrl',
        format: 'json',
        access_token: @access_token,
        group_id: @group_id
      }
      params[:sig] = sign_request(params)
      
      response = HTTParty.get("https://apiok.ru/fb.do", query: params)
      
      if response.parsed_response.is_a?(Hash) && response.parsed_response['error_code']
        puts "✗ Ошибка получения URL загрузки видео: #{response.parsed_response['error_msg']}"
        return nil
      end
      
      upload_url = response.parsed_response['uploadUrl']
      video_id = response.parsed_response['videoId']
      
      # Шаг 2: Загружаем файл
      file_data = File.read(file_path)
      upload_response = HTTParty.post(
        upload_url,
        body: { file: HTTParty::Multipart::File.new(file_data, filename: filename, content_type: 'video/mp4') }
      )
      
      # После загрузки нужно подтвердить через video.save
      save_params = {
        application_key: @application_key,
        method: 'video.save',
        format: 'json',
        access_token: @access_token,
        videoId: video_id,
        groupId: @group_id
      }
      save_params[:sig] = sign_request(save_params)
      
      save_response = HTTParty.post("https://apiok.ru/fb.do", query: save_params)
      
      if save_response.parsed_response.is_a?(Hash) && save_response.parsed_response['error_code']
        puts "✗ Ошибка сохранения видео: #{save_response.parsed_response['error_msg']}"
        return nil
      end
      
      saved_video_id = save_response.parsed_response['videoId']
      
      puts "✓ Видео загружено: video:#{saved_video_id}"
      "video:#{saved_video_id}"
      
    rescue => e
      puts "✗ Ошибка загрузки видео: #{e.message}"
      nil
    end
  end
  
  # Публикация поста через mediatopic.post
  # message: текст поста
  # attachments: массив строк attachments (photo:id, video:id, etc.)
  def post_to_mediatopic(message, attachments)
    begin
      # Формируем строку attachments через запятую
      attachments_str = attachments.join(',')
      
      params = {
        application_key: @application_key,
        method: 'mediatopic.post',
        format: 'json',
        access_token: @access_token,
        gid: @group_id,
        message: message
      }
      
      params[:attachment] = attachments_str unless attachments_str.empty?
      
      params[:sig] = sign_request(params)
      
      response = HTTParty.post("https://apiok.ru/fb.do", query: params)
      
      if response.parsed_response.is_a?(Hash) && response.parsed_response['error_code']
        error_msg = response.parsed_response['error_msg']
        puts "✗ Ошибка публикации поста: #{error_msg}"
        return { success: false, error: error_msg }
      end
      
      topic_id = response.parsed_response['topicId']
      url = "https://ok.ru/group/#{@group_id}/topic/#{topic_id}"
      
      puts "✓ Пост опубликован (ID: #{topic_id})"
      { success: true, topic_id: topic_id, url: url }
      
    rescue => e
      puts "✗ Ошибка публикации поста: #{e.message}"
      { success: false, error: e.message }
    end
  end
end
