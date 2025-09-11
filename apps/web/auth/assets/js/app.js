// OneTimeSecret Auth JavaScript
document.addEventListener('DOMContentLoaded', function() {
  // Auto-hide flash messages after 5 seconds
  const flashMessages = document.querySelectorAll('.flash');
  flashMessages.forEach(function(flash) {
    setTimeout(function() {
      flash.style.transition = 'opacity 0.5s ease-out';
      flash.style.opacity = '0';
      setTimeout(function() {
        flash.remove();
      }, 500);
    }, 5000);
  });

  // Form validation feedback
  const forms = document.querySelectorAll('form');
  forms.forEach(function(form) {
    form.addEventListener('submit', function(e) {
      const submitBtn = form.querySelector('button[type="submit"], input[type="submit"]');
      if (submitBtn) {
        submitBtn.disabled = true;
        submitBtn.textContent = 'Please wait...';
      }
    });
  });

  // Focus management for better accessibility
  const firstInput = document.querySelector('.auth-form input:not([type="hidden"])');
  if (firstInput) {
    firstInput.focus();
  }
});
