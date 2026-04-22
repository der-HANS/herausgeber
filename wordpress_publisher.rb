#!/bin/env ruby
# encoding: utf-8

# WordPress Publisher Module
# Модуль для работы с WordPress через gem rubypress

require 'rubypress'
require 'base64'
require 'set'
require 'mime/types'
require 'uri'

class WordPressPublisher
  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp].freeze
  VIDEO_EXTENSIONS = %w[.mp4 .mov .avi .wmv].freeze

  EMOJI_REGEX = /[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F1E0}-\u{1F1FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/
  
  attr_reader :client, :config

  def initialize(config)
    @config = config
    @client = nil
  end

  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
  # Инициализация соединения с WordPress
  def connect
    begin
      @client = Rubypress::Client.new(
        host: @config['host'],
        username: @config['username'],
        password: @config['password'],
        retry_timeouts: true,
        timeout: 180,
        debug: false,
        use_ssl: true 
      )
      puts "✓ Успешное подключение к WordPress"
      true
    rescue => e
      puts "✗ Ошибка подключения к WordPress: #{e.message}"
      false
    end
  end

  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
  # Загрузка медиафайла на WordPress
  # Возвращает hash с id и url загруженного файла
  def upload_media(file_path, mime_type)
    begin
      file_content = File.read(file_path)
      filename = File.basename(file_path)

      result = @client.uploadFile(:data => {
                    :name => filename,
                    :type => MIME::Types.type_for(file_path).first.to_s,
                    :bits => XMLRPC::Base64.new(IO.read(file_path)),
                    :overwrite => true
      })
      
      if result && result['id']
        puts "✓ Файл загружен: #{filename} (ID: #{result['id']}, URL: #{result['url']})"
        { id: result['id'], url: result['url'] }
      else
        puts "✗ Не удалось загрузить файл: #{filename}"
        nil
      end
    rescue => e
      puts "✗ Ошибка загрузки файла #{file_path}: #{e.message}"
      nil
    end
  end

  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
  # Определение MIME типа по расширению файла
  def get_mime_type(file_path)
    ext = File.extname(file_path).downcase
    case ext
    when '.jpg', '.jpeg'
      'image/jpeg'
    when '.png'
      'image/png'
    when '.gif'
      'image/gif'
    when '.webp'
      'image/webp'
    when '.mp4'
      'video/mp4'
    when '.mov'
      'video/quicktime'
    when '.avi'
      'video/x-msvideo'
    when '.wmv'
      'video/x-ms-wmv'
    else
      'application/octet-stream'
    end
  end

  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
  # Генерация HTML блока для абзаца текста (Gutenberg формат)
  def generate_paragraph_block(text)
    escaped_text = escape_html(text)
    <<-HTML
<!-- wp:paragraph {"className":"ajustify indent","style":{"spacing":{"margin":{"top":"var:preset|spacing|30","bottom":"var:preset|spacing|30"}}}} -->
<p class="ajustify indent" style="margin-top:var(--wp--preset--spacing--30);margin-bottom:var(--wp--preset--spacing--30)">#{escaped_text}</p>
<!-- /wp:paragraph -->
HTML
  end

  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
  # Генерация HTML блока для изображения (Gutenberg формат)
  def generate_image_block(image_id, image_url)
    <<-HTML
<!-- wp:group {"metadata":{"categories":[],"patternName":"core/block/3427","name":"Изображение с рамками"},"style":{"spacing":{"margin":{"top":"var:preset|spacing|30","bottom":"var:preset|spacing|30"}}},"layout":{"type":"constrained"}} -->
<div class="wp-block-group" style="margin-top:var(--wp--preset--spacing--30);margin-bottom:var(--wp--preset--spacing--30)"><!-- wp:image {"id":#{image_id},"sizeSlug":"large","linkDestination":"none","align":"wide","className":"has-lightbox","style":{"border":{"radius":"8px","color":"#6bcae1","width":"2px"},"spacing":{"margin":{"top":"var:preset|spacing|40","bottom":"var:preset|spacing|40"}}}} -->
<figure class="wp-block-image alignwide size-large has-custom-border has-lightbox" style="margin-top:var(--wp--preset--spacing--40);margin-bottom:var(--wp--preset--spacing--40)"><img src="#{image_url}" alt="" class="has-border-color wp-image-#{image_id}" style="border-color:#6bcae1;border-width:2px;border-radius:8px"/></figure>
<!-- /wp:image --></div>
<!-- /wp:group -->
HTML
  end

  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
  # Генерация HTML блока для видео (Gutenberg формат)
  # first_video: true - добавляет autoplay, false - только controls
  def generate_video_block(video_id, video_url, first_video = false)
    autoplay_attr = first_video ? 'autoplay ' : ''
    
    <<-HTML
<!-- wp:group {"metadata":{"categories":[],"patternName":"core/block/4274","name":"Видео"},"style":{"border":{"radius":"5px","color":"#a54200","width":"3px"},"spacing":{"padding":{"top":"0","bottom":"0","left":"0","right":"0"},"margin":{"top":"var:preset|spacing|40","bottom":"var:preset|spacing|40"},"blockGap":"0"},"dimensions":{"minHeight":"0px"},"shadow":"var:preset|shadow|deep"},"layout":{"type":"constrained"}} -->
<div class="wp-block-group has-border-color" style="border-color:#a54200;border-width:3px;border-radius:5px;min-height:0px;margin-top:var(--wp--preset--spacing--40);margin-bottom:var(--wp--preset--spacing--40);padding-top:0;padding-right:0;padding-bottom:0;padding-left:0;box-shadow:var(--wp--preset--shadow--deep)"><!-- wp:video {"id":#{video_id},"style":{"spacing":{"margin":{"top":"0","bottom":"0","left":"0","right":"0"}}}} -->
<figure style="margin-top:0;margin-right:0;margin-bottom:0;margin-left:0" class="wp-block-video"><video #{autoplay_attr}controls src="#{video_url}" playsinline></video></figure>
<!-- /wp:video --></div>
<!-- /wp:group -->
HTML
  end

  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
  # Генерация футера новости (Gutenberg формат)
  def generate_footer_block
    <<-HTML
<!-- wp:separator {"style":{"spacing":{"margin":{"top":"var:preset|spacing|40","bottom":"var:preset|spacing|40"}}}} -->
<hr class="wp-block-separator has-alpha-channel-opacity" style="margin-top:var(--wp--preset--spacing--40);margin-bottom:var(--wp--preset--spacing--40)"/>
<!-- /wp:separator -->

<!-- wp:paragraph -->
<p><em>Больше новостей — в нашем официальном канале в <strong><a href="https://max.ru/id3430030612_gos">мессенджере MAX</a></strong></em></p>
<!-- /wp:paragraph -->
HTML
  end

  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
  # Экранирование HTML специальных символов
  def escape_html(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;').gsub("'", '&#39;')
  end

  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
  # Публикация поста на WordPress
  # title: заголовок поста
  # content: содержимое поста (HTML строка)
  # featured_image_id: ID обложки (может быть nil)
  # status: статус поста ('publish', 'draft', etc.)
  def publish_post(title, content, paragraphs = [], featured_image_id = nil, status = 'publish')
    begin
      # post_data = {
      #   title: title,
      #   description: content,
      #   post_status: status
      # }

      # if featured_image_id
      #   post_data[:thumbnail] = featured_image_id
      # end

      # result = @client.newPost(post_data)

      result = @client.newPost( 
            :blog_id => 0,                                          # 0 unless using WP Multi-Site, then use the blog id
            :content => {
                :post_status  => "publish",
                # :post_date    => @newslist[index][:date],

                :post_content => content,
                :post_title   => title,
                
                :post_thumbnail => featured_image_id,
                :post_excerpt   => ((paragraphs.is_a?(Array) && paragraphs.any? ? paragraphs.first : "").gsub(/<[^>]+>/, '') rescue ""),
                :comment_status => "closed",
                :post_name    => generate_slug(title),
                :post_author  => 1                                  # 1 if there is only the admin user, otherwise the user's id
                # :terms_names  => {
                #     :category   => ['Category One','Category Two','Category Three'],
                #     :post_tag => ['Tag One','Tag Two', 'Tag Three']
                #     }
            }
        )

      if result && !result.to_i.zero?
        post_id = result
        puts "✓ Пост успешно опубликован! ID поста: #{post_id}"

        wppost = @client.getPost(
          :post_id => post_id,
        )
        post_link = (wppost && wppost["link"]) ? URI.decode_www_form_component(wppost["link"]) : nil

        puts "✓ Ссылка на пост: #{post_link}"
        { success: true, url: post_link }
      else
        puts "✗ Не удалось опубликовать пост: #{result.inspect}"
        { success: false, error: result.inspect }
      end
    rescue => e
      puts "✗ Ошибка публикации поста: #{e.message}"
      { success: false, error: e.message }
    end
  end

  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
  # Полный процесс публикации новости
  # title: заголовок
  # paragraphs: массив абзацев текста
  # logo_path: путь к файлу обложки
  # images: массив путей к изображениям
  # videos: массив путей к видеофайлам
  def publish_news(title, paragraphs, logo_path, images = [], videos = [])
    puts "\n=== Начало публикации новости ==="
    puts "Заголовок: #{title}"
    
    # Загрузка обложки
    featured_image_id = nil
    if logo_path && File.exist?(logo_path)
      mime_type = get_mime_type(logo_path)
      media_result = upload_media(logo_path, mime_type)
      featured_image_id = media_result[:id] if media_result
    end

    # Словарь для хранения загруженных медиафайлов по имени файла
    uploaded_media = {}
    
    # Все медиафайлы (изображения и видео) для обработки
    all_media_files = images + videos
    
    # Загружаем все медиафайлы заранее и сохраняем в словарь
    all_media_files.each do |file_path|
      next unless File.exist?(file_path)
      filename = File.basename(file_path)
      mime_type = get_mime_type(file_path)
      media_result = upload_media(file_path, mime_type)
      if media_result
        uploaded_media[filename] = {
          id: media_result[:id],
          url: media_result[:url],
          path: file_path,
          is_video: VIDEO_EXTENSIONS.any? { |ext| file_path.downcase.end_with?(ext) }
        }
      end
    end
    
    # Отслеживаем файлы, которые были использованы во вставках
    used_in_insertions = Set.new
    
    # Формирование контента поста
    content_parts = []
    first_video_global = true
    
    # Добавляем абзацы текста, обрабатывая вставки [имя файла]
    paragraphs.each do |paragraph|
      # Ищем все вставки [имя файла] в абзаце
      insertion_pattern = /\[([^\]]+)\]/
      
      if paragraph.match?(insertion_pattern)
        # Разбиваем абзац на части по вставкам
        parts = paragraph.split(insertion_pattern)
        
        parts.each_with_index do |part, index|
          if index % 2 == 0
            # Это обычный текст (не имя файла)
            unless part.strip.empty?
              content_parts << generate_paragraph_block(part.strip)
            end
          else
            # Это имя файла из вставки [имя файла]
            filename = part.strip
            if uploaded_media.key?(filename)
              media_info = uploaded_media[filename]
              used_in_insertions.add(filename)
              
              if media_info[:is_video]
                content_parts << generate_video_block(media_info[:id], media_info[:url], first_video_global)
                first_video_global = false
              else
                content_parts << generate_image_block(media_info[:id], media_info[:url])
              end
            else
              puts "⚠ Предупреждение: Файл '#{filename}' не найден среди медиафайлов"
            end
          end
        end
      else
        # Обычный абзац без вставок
        next if paragraph.strip.empty?
        content_parts << generate_paragraph_block(paragraph.strip)
      end
    end

    # Добавляем оставшиеся медиафайлы (не использованные во вставках) перед футером
    uploaded_media.each do |filename, media_info|
      unless used_in_insertions.include?(filename)
        if media_info[:is_video]
          content_parts << generate_video_block(media_info[:id], media_info[:url], first_video_global)
          first_video_global = false
        else
          content_parts << generate_image_block(media_info[:id], media_info[:url])
        end
      end
    end

    # Добавляем футер
    content_parts << generate_footer_block

    # Объединяем весь контент
    full_content = content_parts.join("\n\n")

    # Публикация поста
    publish_post(title, full_content, paragraphs, featured_image_id)
  end

  #▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
  def generate_slug(title)
    slug = title.dup
    slug.gsub!(EMOJI_REGEX, '')
    slug.gsub!(/[""«»„""]/, '')
    slug.gsub!(' ', '-')
    slug.gsub!(/-+/, '-')
    slug.gsub!(/^-|-$/, '')
    slug.downcase!
    "/#{slug}"
  end
end
