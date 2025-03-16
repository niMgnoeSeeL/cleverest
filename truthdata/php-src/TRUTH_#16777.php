<?php
$text = new DOMText('my value');
$doc = new DOMDocument();
$doc->appendChild($text);
$text->__construct("\nmy new new value");
$doc->appendChild($text);
$dom2 = new DOMDocument();
$dom2->appendChild($text);
