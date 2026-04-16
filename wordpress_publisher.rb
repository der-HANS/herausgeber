# WordPress Publisher Module
# Модуль для работы с WordPress через gem rubypress

require 'rubypress'
require 'base64'

class WordPressPublisher
  attr_reader :client, :config

  def initialize(config)
    @config = config
    @client = nil
  end

  # Инициализация соединения с WordPress
  def connect
    begin
      @client = Rubypress::Client.new(
        host: @config['host'],
        username: @config['username'],
        password: @config['password']
      )
      puts "✓ Успешное подключение к WordPress"
      true
    rescue => e
      puts "✗ Ошибка подключения к WordPress: #{e.message}"
      false
    end
  end

  # Загрузка медиафайла на WordPress
  # Возвращает hash с id и url загруженного файла
  def upload_media(file_path, mime_type)
    begin
      file_content = File.read(file_path)
      filename = File.basename(file_path)
      
      data = {
        name: filename,
        type: mime_type,
        bits: Base64.strict_encode64(file_content),
        overwrite: true
      }

      result = @client.upload_file(data)
      
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

  # Генерация HTML блока для абзаца текста (Gutenberg формат)
  def generate_paragraph_block(text)
    escaped_text = escape_html(text)
    <<-HTML
<!-- wp:paragraph {"className":"ajustify indent","style":{"spacing":{"margin":{"top":"var:preset|spacing|30","bottom":"var:preset|spacing|30"}}}} -->
<p class="ajustify indent" style="margin-top:var(--wp--preset--spacing--30);margin-bottom:var(--wp--preset--spacing--30)">#{escaped_text}</p>
<!-- /wp:paragraph -->
HTML
  end

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

  # Генерация футера новости (Gutenberg формат)
  def generate_footer_block
    <<-HTML
<!-- wp:separator {"style":{"spacing":{"margin":{"top":"var:preset|spacing|40","bottom":"var:preset|spacing|40"}}}} -->
<hr class="wp-block-separator has-alpha-channel-opacity" style="margin-top:var(--wp--preset--spacing--40);margin-bottom:var(--wp--preset--spacing--40)"/>
<!-- /wp:separator -->

<!-- wp:paragraph -->
<p><em>Более подробная информация и актуальные новости доступны в нашем официальном канале в мессенджере <strong><a href="https://max.ru/id3430030612_gos ">MAX</a></strong></em></p>
<!-- /wp:paragraph -->
HTML
  end

  # Экранирование HTML специальных символов
  def escape_html(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;').gsub("'", '&#39;')
  end

  # Публикация поста на WordPress
  # title: заголовок поста
  # content: содержимое поста (HTML строка)
  # featured_image_id: ID обложки (может быть nil)
  # status: статус поста ('publish', 'draft', etc.)
  def publish_post(title, content, featured_image_id = nil, status = 'publish')
    begin
      post_data = {
        title: title,
        description: content,
        post_status: status
      }

      if featured_image_id
        post_data[:thumbnail] = featured_image_id
      end

      result = @client.new_post(post_data)
      
      if result && result.is_a?(Integer)
        puts "✓ Пост успешно опубликован! ID поста: #{result}"
        { success: true, post_id: result }
      else
        puts "✗ Не удалось опубликовать пост: #{result.inspect}"
        { success: false, error: result.inspect }
      end
    rescue => e
      puts "✗ Ошибка публикации поста: #{e.message}"
      { success: false, error: e.message }
    end
  end

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

    # Формирование контента поста
    content_parts = []
    
    # Добавляем абзацы текста
    paragraphs.each do |paragraph|
      next if paragraph.strip.empty?
      content_parts << generate_paragraph_block(paragraph.strip)
    end

    # Добавляем изображения
    images.each do |image_path|
      next unless File.exist?(image_path)
      mime_type = get_mime_type(image_path)
      media_result = upload_media(image_path, mime_type)
      if media_result
        content_parts << generate_image_block(media_result[:id], media_result[:url])
      end
    end

    # Добавляем видео (первое с autoplay, остальные без)
    videos.each_with_index do |video_path, index|
      next unless File.exist?(video_path)
      mime_type = get_mime_type(video_path)
      media_result = upload_media(video_path, mime_type)
      if media_result
        first_video = (index == 0)
        content_parts << generate_video_block(media_result[:id], media_result[:url], first_video)
      end
    end

    # Добавляем футер
    content_parts << generate_footer_block

    # Объединяем весь контент
    full_content = content_parts.join("\n\n")

    # Публикация поста
    publish_post(title, full_content, featured_image_id)
  end
end
