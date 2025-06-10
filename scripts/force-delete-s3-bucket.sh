#!/bin/bash

BUCKET_NAME="multi-spa-app-dev-static-files-2p2w295d"

echo "S3バケット $BUCKET_NAME の強制削除を開始します..."

# バケットが存在するかチェック
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "バケット $BUCKET_NAME は既に削除されているか、存在しません。"
    exit 0
fi

echo "1. すべてのオブジェクトバージョンを削除中..."

# すべてのオブジェクトバージョンを取得して削除
aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | while read key version_id; do
    if [[ -n "$key" && -n "$version_id" ]]; then
        echo "削除中: $key (バージョン: $version_id)"
        aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id" >/dev/null 2>&1
    fi
done

echo "2. すべての削除マーカーを削除中..."

# すべての削除マーカーを取得して削除
aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text | while read key version_id; do
    if [[ -n "$key" && -n "$version_id" ]]; then
        echo "削除マーカーを削除中: $key (バージョン: $version_id)"
        aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id" >/dev/null 2>&1
    fi
done

echo "3. バケットの最終確認と削除..."

# 念のため、現在のオブジェクトを再度削除
aws s3 rm s3://"$BUCKET_NAME" --recursive >/dev/null 2>&1

# バケットが空であることを確認
OBJECT_COUNT=$(aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --query 'KeyCount' --output text 2>/dev/null || echo "0")
VERSION_COUNT=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'length(Versions)' --output text 2>/dev/null || echo "0")
DELETE_MARKER_COUNT=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'length(DeleteMarkers)' --output text 2>/dev/null || echo "0")

if [[ "$OBJECT_COUNT" == "0" && "$VERSION_COUNT" == "0" && "$DELETE_MARKER_COUNT" == "0" ]]; then
    echo "バケットが空になりました。バケットを削除します..."
    aws s3api delete-bucket --bucket "$BUCKET_NAME"
    if [ $? -eq 0 ]; then
        echo "✅ バケット $BUCKET_NAME が正常に削除されました。"
    else
        echo "❌ バケットの削除に失敗しました。"
        exit 1
    fi
else
    echo "⚠️  バケットが完全に空になっていません。"
    echo "オブジェクト数: $OBJECT_COUNT"
    echo "バージョン数: $VERSION_COUNT"  
    echo "削除マーカー数: $DELETE_MARKER_COUNT"
    echo "手動でバケットの内容を確認してください。"
    exit 1
fi

echo "S3バケットの強制削除が完了しました。"
