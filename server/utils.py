"""
Generic utility functions used across the application.
"""
import random
import re


def generate_seed():
    """Generate a random positive 32-bit integer seed."""
    return random.randint(0, 2**32 - 1)


def sanitize_yaml_response(response_text: str) -> str:
    """
    Sanitize and format AI response into valid YAML.
    Returns properly formatted YAML string.
    """
    
    # Pre-processing: Remove code block markers
    if response_text.startswith("```yaml"):
        # Remove the "```yaml" at the beginning and closing ```
        response_text = response_text[7:]  # Remove "```yaml" (7 characters)
        if response_text.endswith("```"):
            response_text = response_text[:-3]  # Remove closing ```
        response_text = response_text.strip()
    elif response_text.startswith("```"):
        # Remove the "```" at the beginning and closing ```
        response_text = response_text[3:]  # Remove opening ```
        if response_text.endswith("```"):
            response_text = response_text[:-3]  # Remove closing ```
        response_text = response_text.strip()
    
    # Handle edge case where the LLM might have continued the prompt
    # e.g., if the response starts with the incomplete prompt we provided
    if response_text.startswith('title: \\"'):
        # Remove the incomplete prompt prefix
        response_text = response_text[9:].strip()
    
    # Check if it already has a proper YAML structure
    if not response_text.startswith(('title:', 'title :')):
        # Only wrap with title if it doesn't already have one
        # The sanitize function will handle escaping
        response_text = f'title: {response_text}'

    # Split on first occurrence of ``` to handle any remaining code blocks
    response_text = response_text.split("```")[0]

    # Remove any markdown code block indicators and YAML document markers
    clean_text = re.sub(r'```yaml|```|---|\.\.\.$', '', response_text.strip())
    
    # Handle the specific case where LLM duplicates 'title:' in the value
    # e.g., title: "title: "Something"" -> title: "Something"
    clean_text = re.sub(r'title:\s*"title:\s*"([^"]+)""?', r'title: "\1"', clean_text)
    clean_text = re.sub(r'title:\s*\'title:\s*\'([^\']+)\'\'?', r'title: \'\1\'', clean_text)
    clean_text = re.sub(r'title:\s*"title:\s*\'([^\']+)\'"?', r'title: "\1"', clean_text)
    clean_text = re.sub(r'title:\s*\'title:\s*"([^"]+)"\'?', r'title: \'\1\'', clean_text)
    
    # Also handle case where title appears twice without quotes
    clean_text = re.sub(r'title:\s*title:\s*(.+)$', r'title: \1', clean_text, flags=re.MULTILINE)
    
    # Split into lines and process each line
    lines = clean_text.split('\n')
    sanitized_lines = []
    current_field = None
    
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
            
        # Handle field starts
        if stripped.startswith('title:') or stripped.startswith('description:'):
            # Ensure proper YAML format with space after colon and proper quoting
            field_name = stripped.split(':', 1)[0]
            field_value = stripped.split(':', 1)[1].strip()
            
            # Remove outer quotes first
            if (field_value.startswith('"') and field_value.endswith('"')) or \
               (field_value.startswith("'") and field_value.endswith("'")):
                field_value = field_value[1:-1]
            
            # Check for nested title pattern again (in case it wasn't caught by regex)
            if field_name == 'title' and field_value.lower().startswith('title:'):
                # Remove the nested 'title:' prefix
                field_value = field_value[6:].strip().strip('"\'')
            
            # Escape any internal quotes
            field_value = field_value.replace('"', '\\"')
            
            # Always quote the value to ensure proper YAML formatting
            field_value = f'"{field_value}"'
                
            sanitized_lines.append(f"{field_name}: {field_value}")
            current_field = field_name
            
        elif stripped.startswith('tags:'):
            sanitized_lines.append('tags:')
            current_field = 'tags'
            
        elif stripped.startswith('-') and current_field == 'tags':
            # Process tag values
            tag = stripped[1:].strip().strip('"\'')
            if tag:
                # Clean and format tag
                tag = re.sub(r'[^\x00-\x7F]+', '', tag)  # Remove non-ASCII
                tag = re.sub(r'[^a-zA-Z0-9\s-]', '', tag)  # Keep only alphanumeric and hyphen
                tag = tag.strip().lower().replace(' ', '-')
                if tag:
                    sanitized_lines.append(f"  - {tag}")
                    
        elif current_field in ['title', 'description']:
            # Handle multi-line title/description continuation
            value = stripped.strip('"\'')
            if value:
                # Append to previous line (but within the quotes)
                prev = sanitized_lines[-1]
                # Remove the closing quote, append the value, and add the quote back
                if prev.endswith('"'):
                    sanitized_lines[-1] = f'{prev[:-1]} {value}"'
    
    # Ensure the YAML has all required fields
    required_fields = {'title', 'description', 'tags'}
    found_fields = {line.split(':')[0].strip() for line in sanitized_lines if ':' in line}
    
    for field in required_fields - found_fields:
        if field == 'tags':
            sanitized_lines.extend(['tags:', '  - default'])
        else:
            sanitized_lines.append(f'{field}: "No {field} provided"')
    
    return '\n'.join(sanitized_lines)