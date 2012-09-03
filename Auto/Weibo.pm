package Auto::Weibo;

use warnings;
use strict;
use Data::Dumper;

use LWP::UserAgent;
use JSON qw/from_json/;
use Digest::SHA1 qw/sha1 sha1_hex sha1_base64/;
use URI::Escape qw/uri_escape/;
use MIME::Base64;
use Encode;
use Encode::CN;
use URI::Escape qw/uri_escape/;
use http_query;
use http_util;
use base qw/Class::Accessor::Fast/;

__PACKAGE__->mk_accessors('username','password');

our $DEBUG = 1;   # 整个程序的 debug 开关
$http_query_debug = 0;

sub new {
    my ($class, $username, $password) = @_;
    my $self = {};
    $self->{username}   = $username,
    $self->{password}   = $password,
    
    bless $self, $class;
}


sub do_login {
    my ($self ) = @_;
    set_user_agent('Mozilla/5.0 (X11; Linux i686; rv:8.0) Gecko/20100101 Firefox/8.0' );
    my $url = 'http://login.sina.com.cn/sso/login.php?client=ssologin.js(v1.3.18)';

    my $post_data = {
        entry => 'weibo',
        gateway => 1,
        from => '',
        savestate => 7,
        userticket => 1,
        ssosimplelogin => 1,
        vsnf => 1,
        vsnval => '',
        su => '',
        service => 'miniblog',
        servertime => '',
        nonce => '',
        pwencode => 'wsse',
        sp => '',
        encoding => 'UTF-8',
        url => uri_escape('http://weibo.com/ajaxlogin.php?framelogin=1&callback=parent.sinaSSOController.feedBackUrlCallBack'),
        returntype => 'META',
        returntype => 'METAa',
        
    };

    my ($servertime, $nonce) = get_servertime();
    my $pwd = get_pwd($self->{password}, $servertime, $nonce);

    $post_data->{servertime} = $servertime;
    $post_data->{nonce} = $nonce;
    $post_data->{su} = get_user( $self->{username} );
    $post_data->{sp} = $pwd;

    # 开始登陆，
    my ($headers, $content, $status) = http_query($url,'POST',  hash_to_paired_string($post_data));
    my $location = $1 if $content =~ m#location.replace\('(.*?)'\)#;
    ($headers, $content, $status) = http_query($location);
    if ( $DEBUG ){
        print "$headers, $content, $status\n";
    }
}



# get_fans_by_uid('2634647053');
# get_follow('2748072245');
# do_un_follow('1883096521','北漂的大燕子', '2748072245');
# post_message('2748072245', '今天晚上要早点回家');

#  2748072245  mc cheung uid

#-------------------------------------------------------
sub post_message {
    my ($self, $uid, $msg ) = @_;
    
    my $post = {
        appkey      => '', 
        style_type  => 0,
        text        => $msg,
        rank        => '',
        location    => 'profile',
        module      => 'shissue',
        pub_type    => 'dialog',
        _t          => 0,
    };

    my $url = 'http://weibo.com/aj/mblog/add?__rnd=' . time;
    set_referer("http://weibo.com/$uid/profile?topnav=1&wvr=3.6"); 
    my ($header, $body, $status) = http_query($url, 'POST', hash_to_paired_string($post));
    
    debug_logs( from_json($body));
}
    

sub debug_logs {
    my $info = shift;
    if ($DEBUG){
        foreach ( keys %$info){
            print "$_ : $info->{$_}\t";
        }
        print "\n";
    }
}

# ------------------------
# 这里只取第一页的 follow, 
# 如果没有，则说明，现在没
# 有关注的人, 调用的时候
# 悠着点。 别太快
# ------------------------
sub do_un_follow {
    my ($self, $uid, $fnick, $ouid ) = @_;
    
    my $post = {
        uid => $uid,
        f       => 0,
        extra   => '',
        oid     => $ouid,
        fnick   => $fnick,
        location => 'myfollow'
    };

    my $url = 'http://www.weibo.com/aj/f/unfollow';
    set_referer("http://www.weibo.com/$ouid/follow?leftnav=1&wvr=3.6");
    my ($header, $body, $status) = http_query($url, 'POST', hash_to_paired_string($post));
    
    if ($DEBUG){
        my $json = from_json($body);
        print "Unfollow $fnick, Code: $json->{code}, Msg: $json->{msg}\n" ;
    }
}


sub get_follow {
    my ($self, $uid) = @_;
    my $url = "http://www.weibo.com/$uid/follow?leftnav=1&wvr=3.6";

    my ($header, $body, $status) = http_query($url);
    $body = encode('utf8', decode('gbk', $body));
    my $users = _get_user_info($body);
    return $users;
}


# -----------------------
# do followed 需要2个参数，
# 一个用户信息，一个是用户
# 是谁的听众
# -----------------------
sub do_follow {
    my ($self, $uid, $fnick, $oid) = @_;
    my $url = 'http://www.weibo.com/aj/f/followed?__rnd=' . time ;
    my $post = {
        uid     => $uid,
        f       => 1,
        extra   => '',
        oid     => $oid,
        fnick   => $fnick,
        location => 'fans',
        refer_sort => 'followed',
        '_t'    => 0
    };

    my ($header, $content, $status)  = http_query($url, 'POST', hash_to_paired_string($post));
    my $json = from_json($content);
    
    if ($json->{code} eq '100000' && $status == 200){
        print "Follow $uid, $fnick done\n" if $DEBUG;
    }else{
        print "Follow $uid, $fnick Error\n" . $json->{msg} if $DEBUG;
    }
}



sub get_fans_by_uid {
    my ($self, $uid, $page) = @_;
    $page ||= 1;
    my $url = "http://www.weibo.com/$uid/fans?page=$page";
    my $content = (http_query($url))[1];
    
    my $users = _get_user_info($content, $uid);
    
    # 执行关注相关的工作
    foreach my $user ( keys %$users){
        print "$user\n";
        set_referer($url);
        do_follow($user, $users->{$user}->{fnick}, $uid);
        
        # 不能太快啊， Weibo 会骂的
        # 稍休息一会
        my $rand = int( rand(90));
        $rand = 15 if $rand < 5;
        sleep($rand);
    }
}

sub convert_unicode_to_utf8 {
    my $str_o = shift;
    my $str;
    my @char = split /\\u/, $str_o;
    foreach ( @char ){
        my $int = $1 if /(\d+)/;
        next if length($int) != 4;
        my $w = chr( eval( '0x' . $int ));
        $str .= $w;
    }
    $str = encode('utf8', $str);
    return $str;
}


sub _get_user_info {
    my ($content, $oid) = @_;
    my $users = {};
    while ($content =~ m#uid=(\d+)&fnick=(.*?)&sex=([mf])#g) {
        $users->{$1}->{fnick} = convert_unicode_to_utf8($2);
        $users->{$1}->{sex} = $3;
        $users->{$1}->{oid} = $oid;
    }
    
    while ($content =~ m#uid=(\d+)&nick=(.*?)&online_state=(\d)#g) {
        $users->{$1}->{nick} = convert_unicode_to_utf8($2);
        $users->{$1}->{sex} = $3;
        $users->{$1}->{online_state} = $3;
        $users->{$1}->{oid} = $oid;
    }
    return $users;
}


sub get_servertime {
    my $self = shift;
    my $url = 'http://login.sina.com.cn/sso/prelogin.php?entry=weibo&callback=sinaSSOController.preloginCallBack&su=dW5kZWZpbmVk&client=ssologin.js(v1.3.18)&_=1329806375939';
    my $res = (http_query($url))[1];
    
    my $p = $1 if $res =~ /\((.*)\)/;
    $p = from_json($p);

    my $servertime = $p->{servertime};
    my $nonce = $p->{nonce};
    return ($servertime, $nonce);
}

sub get_pwd {
    my ($pwd, $server_time, $nonce) = @_;

    $pwd = sha1_hex(sha1_hex($pwd));
    $pwd .= $server_time . $nonce;
    $pwd = sha1_hex($pwd);

    return $pwd;
}

sub get_user {
    my ($username) = @_;

    $username = uri_escape($username);
    $username = encode_base64($username);
    chomp($username);
    $username = uri_escape($username);
    return $username;
}

1;
