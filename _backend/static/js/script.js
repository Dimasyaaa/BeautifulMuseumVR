document.addEventListener('DOMContentLoaded', function() {
    
    // Логика живого предпросмотра изображения 
    const imageUrlInput = document.getElementById('image_url');
    const previewImg = document.getElementById('preview_img');
    const placeholderText = document.getElementById('preview_placeholder');

    if (imageUrlInput && previewImg) {
        // Функция обновления превью
        function updatePreview() {
            const url = imageUrlInput.value.trim();
            
            if (url) {
                // Показываем картинку, скрываем текст
                previewImg.src = url;
                previewImg.style.display = 'block';
                if (placeholderText) placeholderText.style.display = 'none';
                
                // Обработка ошибки загрузки (битая ссылка)
                previewImg.onerror = function() {
                    previewImg.style.display = 'none';
                    if (placeholderText) {
                        placeholderText.style.display = 'block';
                        placeholderText.innerHTML = '<i class="bi bi-exclamation-triangle text-warning"></i><br>Не удалось загрузить изображение';
                    }
                };
            } else {
                // Если поле пустое, возвращаем как было
                previewImg.style.display = 'none';
                if (placeholderText) {
                    placeholderText.style.display = 'block';
                    placeholderText.innerHTML = '<i class="bi bi-image display-4"></i><br>Изображение появится здесь';
                }
            }
        }

        // Слушаем ввод текста (с небольшой задержкой, чтобы не дергать сеть при каждом символе)
        let timeout = null;
        imageUrlInput.addEventListener('input', function() {
            clearTimeout(timeout);
            timeout = setTimeout(updatePreview, 500); // Ждем 500мс после окончания ввода
        });

        // Запускаем один раз при загрузке страницы (если редактируем существующий экспонат)
        updatePreview();
    }

    // Подтверждение удаления с красивой анимацией 
    const deleteForms = document.querySelectorAll('form[action*="/delete"]');
    deleteForms.forEach(form => {
        form.addEventListener('submit', function(e) {
            if (!confirm('Вы уверены, что хотите удалить этот экспонат? Это действие нельзя отменить.')) {
                e.preventDefault();
            }
        });
    });
});