$(document).ready(function () {
  $.fn.exists = function () { return this.length !== 0;  };
  var params = window.params;

  // Connect to the server
  var es = new EventSource('/generate' + '?' + $.param(params));

  // We don't want the user reloading and regenerating the same file,
  // so set our history to the homepage.
  history.pushState({ uuid: params.uuid }, 'ficrip', '/simple');

  // Report an error
  es.addEventListener('error', function (e) {
    $('#content').fadeOut(1000, function() {
      $('#content').replaceWith('<div id="content" style="display: none">' + e.data + '</div>');
      $('#content').fadeIn(2000);
    });
  });

  // Update progressbar
  es.addEventListener('progress', function (e) {
    var p = $('#progress');
    if (e.data === 'null') {
      p.removeClass('determinate').addClass('indeterminate');
    } else if ( p.hasClass('indeterminate')) {
      p.removeClass('indeterminate').addClass('determinate').css('width', e.data);
    } else {
      p.css('width', e.data);
    }
  });

  // Navigate to new URL
  es.addEventListener('url', function (e) { console.log(e.data); window.location = e.data; });

  // Close the connection
  es.addEventListener('close', function () { es.close(); });

  // Add a back button when download is complete
  es.addEventListener('backbutton', function () {
    $('#footeritem').fadeOut(1000, function () {
      $('#footeritem').replaceWith('<a href="/" class="grey-text">back</a>');
      $('#footeritem').fadeIn(1000);
    });
  });

  // Update the page with the title/author info
  es.addEventListener('info', function (e) {
    var info = $.parseJSON(e.data);
    var replaceTitleSubtitle = function () {
      $('#title').replaceWith('<span id="title" style="display: none">' + info.title + '</span>');
      $('#subtitle').replaceWith('<span id="subtitle" style="display: none">&nbsp; by ' + info.author + '</span>');
    };

    var mf = $('main').add('footer');
    var ts = $('#title').add('#subtitle');
    var fadeInTitleSubtitle = function () {
      replaceTitleSubtitle();
      ts = $('#title').add('#subtitle');
      if (!mf.is('visible')) {
        ts = $('main').add('footer').add('#title').add('#subtitle');
      }
      ts.fadeIn(1000);
    };

    if (ts.is('visible')) {
      ts.fadeOut(1000, function () {
        fadeInTitleSubtitle()
      });
    } else {
      fadeInTitleSubtitle();
    }

  });
});
