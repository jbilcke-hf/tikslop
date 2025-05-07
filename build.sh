#!/bin/bash
# Script to build Flutter web app with cache busting

echo "🔨 Building Flutter web app..."
flutter build web --release

# for debugging, use:
#flutter build web --profile

# Check if the build was successful
if [ $? -ne 0 ]; then
  echo "❌ Flutter build failed!"
  exit 1
fi

# Generate timestamp
TIMESTAMP=$(date +%s)

# Replace BUILD_TIMESTAMP in index.html with the current timestamp
echo "📝 Adding build timestamp ($TIMESTAMP) for cache busting..."
sed -i.bak "s/BUILD_TIMESTAMP/$TIMESTAMP/g" build/web/index.html
rm build/web/index.html.bak

echo "✅ Flutter build complete!"
echo "🚀 Next step: commit build/web and push to Hugging Face!"