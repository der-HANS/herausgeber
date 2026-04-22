# Herausgeber Agent Guidelines

## Essential Commands
- Run publisher: `ruby herausgeber.rb [content_folder_path]`
- Run with test data: `ruby herausgeber.rb test_content`
- Install dependencies: `bundle install`

## Configuration
- Requires `config.yml` in parent directory of script
- Never commit `config.yml` (contains credentials)
- Minimum WordPress config:
  ```yaml
  wordpress:
    host: "https://yoursite.com/xmlrpc.php"
    username: "your_username"
    password: "your_password"
  ```
- Optional platform configs (VK, OK, MAX) in same file

## Content Requirements
Exactly one each in content folder:
- Image file containing `_logo.` in name (e.g., `news_logo.jpg`)
- Text file `.txt` (first line = title, subsequent lines = paragraphs)
Any number of:
- Additional images (.jpg, .png, .gif, .webp)
- Videos (.mp4, .mov, .avi, .wmv)

## Execution Flow
1. Load config from `../config.yml`
2. Scan content directory for required files
3. Parse text file (title + paragraphs)
4. Interactive platform selection loop:
   - 1: WordPress (pnisurov.ru)
   - 2: VKontakte
   - 3: Odnoklassniki
   - 4: MAX Messenger
   - 0: Exit and show publication report
5. After exit, displays success/failure report for each platform

## Important Notes
- Program validates: single logo image, single txt file, config validity
- Errors halt execution with descriptive messages
- Test folder `test_content` contains sample data for safe testing
- All publishers require platform-specific tokens in config.yml
- Before applying and saving any changes to source files, show these changes and ask for confirmation of the changes.
- Use Russian when communicating with users.
- All messages and comments in the program must be written in Russian.
- Write your "Thinking" in Russian