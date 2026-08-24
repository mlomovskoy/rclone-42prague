// The contact address is stored reversed so that simple e-mail
// harvesters that read the raw HTML do not find a usable address.
(function () {
  function rev(s) { return s.split('').reverse().join(''); }
  document.querySelectorAll('span.email').forEach(function (el) {
    var addr = rev(el.getAttribute('data-u')) + '@' + rev(el.getAttribute('data-d'));
    var a = document.createElement('a');
    a.href = 'mailto:' + addr;
    a.textContent = addr;
    el.replaceWith(a);
  });
})();
